//! Phoenix WebSocket implementation for Rust.

use crate::error::{Result, SensoctoError};
use crate::models::{PhoenixMessage, PhoenixReply};
use futures_util::{SinkExt, StreamExt};
use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use tokio::net::TcpStream;
use tokio::sync::{mpsc, oneshot, RwLock};
use tokio::time::{timeout, Duration};
use tokio_tungstenite::{
    connect_async, tungstenite::Message, MaybeTlsStream, WebSocketStream,
};
use tracing::{debug, error, info, warn};

type WsStream = WebSocketStream<MaybeTlsStream<TcpStream>>;
type EventHandler = Box<dyn Fn(serde_json::Value) + Send + Sync>;

/// Phoenix WebSocket client.
pub struct PhoenixSocket {
    url: String,
    heartbeat_interval: Duration,
    write_tx: Option<mpsc::Sender<Message>>,
    pending_replies: Arc<RwLock<HashMap<String, oneshot::Sender<PhoenixReply>>>>,
    event_handlers: Arc<RwLock<HashMap<String, Vec<EventHandler>>>>,
    ref_counter: Arc<AtomicU64>,
    connected: Arc<RwLock<bool>>,
}

impl PhoenixSocket {
    /// Creates a new Phoenix socket.
    pub fn new(url: String, heartbeat_interval: Duration) -> Self {
        Self {
            url,
            heartbeat_interval,
            write_tx: None,
            pending_replies: Arc::new(RwLock::new(HashMap::new())),
            event_handlers: Arc::new(RwLock::new(HashMap::new())),
            ref_counter: Arc::new(AtomicU64::new(0)),
            connected: Arc::new(RwLock::new(false)),
        }
    }

    /// Connects to the Phoenix server.
    pub async fn connect(&mut self) -> Result<()> {
        info!("Connecting to {}", self.url);

        let (ws_stream, _) = connect_async(&self.url).await?;
        let (write, read) = ws_stream.split();

        let (write_tx, write_rx) = mpsc::channel::<Message>(100);
        self.write_tx = Some(write_tx);

        *self.connected.write().await = true;

        // Spawn write task
        let connected = self.connected.clone();
        tokio::spawn(async move {
            Self::write_loop(write, write_rx, connected).await;
        });

        // Spawn read task
        let pending = self.pending_replies.clone();
        let handlers = self.event_handlers.clone();
        let connected = self.connected.clone();
        tokio::spawn(async move {
            Self::read_loop(read, pending, handlers, connected).await;
        });

        // Spawn heartbeat task
        let write_tx = self.write_tx.clone();
        let heartbeat_interval = self.heartbeat_interval;
        let ref_counter = self.ref_counter.clone();
        let connected = self.connected.clone();
        tokio::spawn(async move {
            Self::heartbeat_loop(write_tx, heartbeat_interval, ref_counter, connected).await;
        });

        info!("Connected to Phoenix server");
        Ok(())
    }

    /// Disconnects from the Phoenix server.
    pub async fn disconnect(&mut self) {
        *self.connected.write().await = false;
        self.write_tx = None;
        info!("Disconnected from Phoenix server");
    }

    /// Returns whether the socket is connected.
    pub async fn is_connected(&self) -> bool {
        *self.connected.read().await
    }

    /// Sends a message and waits for a reply.
    pub async fn send(
        &self,
        topic: &str,
        event: &str,
        payload: serde_json::Value,
    ) -> Result<PhoenixReply> {
        let msg_ref = self.generate_ref();

        let message = PhoenixMessage {
            topic: topic.to_string(),
            event: event.to_string(),
            payload,
            msg_ref: Some(msg_ref.clone()),
        };

        let json = serde_json::to_string(&message)?;
        debug!("Sending: {}", json);

        let (tx, rx) = oneshot::channel();
        self.pending_replies.write().await.insert(msg_ref.clone(), tx);

        if let Some(write_tx) = &self.write_tx {
            write_tx
                .send(Message::Text(json))
                .await
                .map_err(|e| SensoctoError::ChannelSendError(e.to_string()))?;
        } else {
            return Err(SensoctoError::Disconnected);
        }

        // Wait for reply with timeout
        match timeout(Duration::from_secs(10), rx).await {
            Ok(Ok(reply)) => Ok(reply),
            Ok(Err(_)) => Err(SensoctoError::Other("Reply channel closed".into())),
            Err(_) => {
                self.pending_replies.write().await.remove(&msg_ref);
                Err(SensoctoError::Timeout(10000))
            }
        }
    }

    /// Sends a message without waiting for a reply.
    pub async fn send_no_reply(
        &self,
        topic: &str,
        event: &str,
        payload: serde_json::Value,
    ) -> Result<()> {
        let msg_ref = self.generate_ref();

        let message = PhoenixMessage {
            topic: topic.to_string(),
            event: event.to_string(),
            payload,
            msg_ref: Some(msg_ref),
        };

        let json = serde_json::to_string(&message)?;

        if let Some(write_tx) = &self.write_tx {
            write_tx
                .send(Message::Text(json))
                .await
                .map_err(|e| SensoctoError::ChannelSendError(e.to_string()))?;
        } else {
            return Err(SensoctoError::Disconnected);
        }

        Ok(())
    }

    /// Registers an event handler for a topic.
    pub async fn on<F>(&self, topic: &str, event: &str, handler: F)
    where
        F: Fn(serde_json::Value) + Send + Sync + 'static,
    {
        let key = format!("{}:{}", topic, event);
        let mut handlers = self.event_handlers.write().await;
        handlers
            .entry(key)
            .or_insert_with(Vec::new)
            .push(Box::new(handler));
    }

    fn generate_ref(&self) -> String {
        self.ref_counter.fetch_add(1, Ordering::SeqCst).to_string()
    }

    async fn write_loop(
        mut write: futures_util::stream::SplitSink<WsStream, Message>,
        mut rx: mpsc::Receiver<Message>,
        connected: Arc<RwLock<bool>>,
    ) {
        while let Some(msg) = rx.recv().await {
            if !*connected.read().await {
                break;
            }

            if let Err(e) = write.send(msg).await {
                error!("Write error: {}", e);
                break;
            }
        }
    }

    async fn read_loop(
        mut read: futures_util::stream::SplitStream<WsStream>,
        pending: Arc<RwLock<HashMap<String, oneshot::Sender<PhoenixReply>>>>,
        handlers: Arc<RwLock<HashMap<String, Vec<EventHandler>>>>,
        connected: Arc<RwLock<bool>>,
    ) {
        while let Some(result) = read.next().await {
            if !*connected.read().await {
                break;
            }

            match result {
                Ok(Message::Text(text)) => {
                    debug!("Received: {}", text);

                    if let Ok(msg) = serde_json::from_str::<PhoenixMessage>(&text) {
                        // Handle reply
                        if msg.event == "phx_reply" {
                            if let Some(msg_ref) = &msg.msg_ref {
                                if let Some(tx) = pending.write().await.remove(msg_ref) {
                                    if let Ok(reply) =
                                        serde_json::from_value::<PhoenixReply>(msg.payload)
                                    {
                                        let _ = tx.send(reply);
                                    }
                                }
                            }
                        } else {
                            // Dispatch to handlers
                            let key = format!("{}:{}", msg.topic, msg.event);
                            if let Some(event_handlers) = handlers.read().await.get(&key) {
                                for handler in event_handlers {
                                    handler(msg.payload.clone());
                                }
                            }
                        }
                    }
                }
                Ok(Message::Close(_)) => {
                    info!("WebSocket closed by server");
                    *connected.write().await = false;
                    break;
                }
                Ok(Message::Ping(data)) => {
                    debug!("Received ping");
                    // Pong is handled automatically by tungstenite
                    let _ = data;
                }
                Err(e) => {
                    error!("Read error: {}", e);
                    *connected.write().await = false;
                    break;
                }
                _ => {}
            }
        }
    }

    async fn heartbeat_loop(
        write_tx: Option<mpsc::Sender<Message>>,
        interval: Duration,
        ref_counter: Arc<AtomicU64>,
        connected: Arc<RwLock<bool>>,
    ) {
        let mut interval_timer = tokio::time::interval(interval);

        loop {
            interval_timer.tick().await;

            if !*connected.read().await {
                break;
            }

            if let Some(tx) = &write_tx {
                let msg_ref = ref_counter.fetch_add(1, Ordering::SeqCst).to_string();
                let message = PhoenixMessage {
                    topic: "phoenix".to_string(),
                    event: "heartbeat".to_string(),
                    payload: serde_json::json!({}),
                    msg_ref: Some(msg_ref),
                };

                if let Ok(json) = serde_json::to_string(&message) {
                    if tx.send(Message::Text(json)).await.is_err() {
                        warn!("Failed to send heartbeat");
                        break;
                    }
                }
            } else {
                break;
            }
        }
    }
}
