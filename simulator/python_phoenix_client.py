import asyncio
import json
import time
import logging
import random
import websockets  # Correct library name
from collections import deque
from typing import Callable, Optional, Dict, Any, List

logging.basicConfig(level=logging.INFO)


class BackpressureConfig:
    """Stores backpressure configuration received from the server."""

    def __init__(self):
        self.attention_level = "none"
        self.batch_window_ms = 5000  # Default: 5 seconds
        self.batch_size = 20  # Default: large batches
        self.timestamp = 0

    def update(self, config: dict):
        """Update configuration from server message."""
        self.attention_level = config.get("attention_level", self.attention_level)
        self.batch_window_ms = config.get("recommended_batch_window", self.batch_window_ms)
        self.batch_size = config.get("recommended_batch_size", self.batch_size)
        self.timestamp = config.get("timestamp", time.time() * 1000)
        logging.info(
            f"Backpressure config updated: level={self.attention_level}, "
            f"window={self.batch_window_ms}ms, batch_size={self.batch_size}"
        )


class PhoenixChannelClient:
    def __init__(self, socket_url, on_message_callback, on_connect_callback=None, on_disconnect_callback=None):
        self.socket_url = socket_url
        self.on_message_callback = on_message_callback
        self.on_connect_callback = on_connect_callback
        self.on_disconnect_callback = on_disconnect_callback
        self.channels = {}
        self.ws = None
        self.lock = asyncio.Lock()
        self.connected = False
        self.receiving_task = None  # Task for receiving messages
        self.reconnect_delay = 2 # Default reconnect delay

        # Backpressure support
        self.backpressure_configs: Dict[str, BackpressureConfig] = {}
        self.message_queues: Dict[str, deque] = {}
        self.batch_tasks: Dict[str, asyncio.Task] = {}
        self.on_backpressure_callback: Optional[Callable] = None

    async def connect(self):
        while True:
            try:
                self.ws = await websockets.connect(self.socket_url)
                logging.info("WebSocket connection opened")
                self.connected = True
                if self.on_connect_callback:
                    await self.on_connect_callback()

                await self._join_all_channels()
                self.receiving_task = asyncio.create_task(self._receive_messages())
                break  # Connection successful, exit loop
            except websockets.ConnectionClosed as e:
                logging.info(f"WebSocket connection closed: {e}")
                self.connected = False
                if self.on_disconnect_callback:
                    await self.on_disconnect_callback()
                await asyncio.sleep(self.reconnect_delay)  # Wait before retrying
                logging.info(f"Attempting to reconnect in {self.reconnect_delay} seconds...")


            except Exception as e:
                #logging.error(f"An error occurred: {e}")
                logging.error(e, exc_info=True)
                self.connected = False
                if self.on_disconnect_callback:
                    await self.on_disconnect_callback()
                await asyncio.sleep(self.reconnect_delay)  # Wait before retrying
                logging.info(f"Attempting to reconnect in {self.reconnect_delay} seconds...")

    async def _join_all_channels(self):
        for topic, params in list(self.channels.items()):
             await self._join_channel(topic, params)

    async def _receive_messages(self):
        try:
            async for message in self.ws:
                try:
                    data = json.loads(message)
                    topic = data.get("topic")
                    event = data.get("event")
                    payload = data.get("payload")

                    # Handle backpressure_config events from server
                    if event == "backpressure_config" and payload:
                        self._handle_backpressure_config(topic, payload)

                    if topic and event:
                        self.on_message_callback(topic, event, payload)
                except json.JSONDecodeError as e:
                    logging.error(f"Error decoding JSON: {message}, {e}")
        except Exception as e:
            logging.error(f"Error receiving messages, closing connection: {e}")
            self.connected = False
            if self.on_disconnect_callback:
                await self.on_disconnect_callback()
            await self.close()

    def _handle_backpressure_config(self, topic: str, payload: dict):
        """Handle backpressure configuration updates from server."""
        if topic not in self.backpressure_configs:
            self.backpressure_configs[topic] = BackpressureConfig()
        self.backpressure_configs[topic].update(payload)

        # Notify callback if set
        if self.on_backpressure_callback:
            self.on_backpressure_callback(topic, self.backpressure_configs[topic])

    def get_backpressure_config(self, topic: str) -> BackpressureConfig:
        """Get current backpressure config for a topic."""
        if topic not in self.backpressure_configs:
            self.backpressure_configs[topic] = BackpressureConfig()
        return self.backpressure_configs[topic]

    def set_backpressure_callback(self, callback: Callable):
        """Set callback for backpressure config changes."""
        self.on_backpressure_callback = callback

    async def _join_channel(self, topic, params):
        try:
            async with self.lock:
                logging.info(f"Joining channel: {topic}")
                payload = {"topic": topic, "event": "phx_join", "payload": params, "ref": str(time.time())}
                await self.ws.send(json.dumps(payload))
        except Exception as e:
            logging.error(f"Error joining channel {topic}: {e}")

    async def subscribe(self, topic, params):
        async with self.lock:
             if topic not in self.channels:
                self.channels[topic] = params


    async def unsubscribe(self, topic):
        async with self.lock:
            if topic in self.channels:
                logging.info(f"Unsubscribing from channel: {topic}")
                del self.channels[topic]
                payload = {"topic": topic, "event": "phx_leave", "payload": {}, "ref": str(time.time())}
                if self.connected:
                  await self.ws.send(json.dumps(payload))


    async def push(self, topic, event, payload):
         async with self.lock:
            if self.ws and self.connected and not self.ws.closed:
                try:
                   logging.info(f"Pushing event: {event} on topic: {topic}, with payload: {payload}")
                   push_payload = {"topic": topic, "event": event, "payload": payload, "ref": str(time.time())}
                   await self.ws.send(json.dumps(push_payload))
                except Exception as e:
                    logging.error(f"Error pushing message {event} on {topic}: {e}")
                    self.connected = False

    async def push_with_backpressure(self, topic: str, event: str, payload: dict):
        """
        Push a message respecting backpressure configuration.
        Messages are queued and sent in batches according to server recommendations.
        """
        # Initialize queue for this topic if needed
        if topic not in self.message_queues:
            self.message_queues[topic] = deque()

        # Add message to queue
        self.message_queues[topic].append({
            "event": event,
            "payload": payload,
            "queued_at": time.time() * 1000
        })

        # Get backpressure config
        config = self.get_backpressure_config(topic)

        # Check if we should flush immediately (batch size reached)
        if len(self.message_queues[topic]) >= config.batch_size:
            await self._flush_queue(topic)
        else:
            # Start batch timer if not already running
            self._ensure_batch_timer(topic)

    def _ensure_batch_timer(self, topic: str):
        """Ensure a batch timer is running for the topic."""
        if topic in self.batch_tasks and not self.batch_tasks[topic].done():
            return  # Timer already running

        config = self.get_backpressure_config(topic)
        self.batch_tasks[topic] = asyncio.create_task(
            self._batch_timer(topic, config.batch_window_ms)
        )

    async def _batch_timer(self, topic: str, window_ms: int):
        """Timer that flushes the queue after the batch window expires."""
        await asyncio.sleep(window_ms / 1000.0)
        if topic in self.message_queues and len(self.message_queues[topic]) > 0:
            await self._flush_queue(topic)

    async def _flush_queue(self, topic: str):
        """Flush all queued messages for a topic as a batch."""
        if topic not in self.message_queues:
            return

        queue = self.message_queues[topic]
        if len(queue) == 0:
            return

        # Collect all messages
        messages = []
        while len(queue) > 0:
            msg = queue.popleft()
            messages.append(msg["payload"])

        # Send as batch or individual based on count
        if len(messages) == 1:
            await self.push(topic, "measurement", messages[0])
        else:
            await self.push(topic, "measurements_batch", messages)
            logging.info(f"Flushed batch of {len(messages)} messages for {topic}")

    async def close(self):
        # Cancel all batch timers
        for task in self.batch_tasks.values():
            if not task.done():
                task.cancel()

        # Flush remaining queues
        for topic in list(self.message_queues.keys()):
            await self._flush_queue(topic)

        if self.ws:
            await self.ws.close()
            self.connected = False
            if self.receiving_task:
                self.receiving_task.cancel()


def handle_message(topic, event, payload):
    logging.info(f"Received message on topic: {topic}, event: {event}, payload: {payload}")

async def on_connect():
    logging.info("Client connected to websocket.")


async def on_disconnect():
    logging.info("Client disconnected from websocket.")


async def main():
    socket_url = "ws://localhost:4000/socket/websocket"
    client = PhoenixChannelClient(socket_url, handle_message, on_connect, on_disconnect)

    logging.info(f"Before client init")
   # Subscribe to some channels, this will ensure that the channels exist before the client connects.
    await client.subscribe("sensor_data:sensor_1", {"device_name": "sensor_1"})
    #await client.subscribe("sensor_data:sensor_2", {"device_name": "sensor_2"})
    #await client.subscribe("sensor_data:sensor_3", {"device_name": "sensor_3"})

    await client.connect()
    logging.info(f"After client init")

    await client.close()


if __name__ == "__main__":
    asyncio.run(main())