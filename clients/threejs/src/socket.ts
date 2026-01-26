/**
 * Phoenix WebSocket implementation for TypeScript.
 * @module socket
 */

import { ConnectionError, TimeoutError } from "./errors.js";

/**
 * Phoenix protocol message structure.
 */
export interface PhoenixMessage {
  topic: string;
  event: string;
  payload: unknown;
  ref: string | null;
}

/**
 * Response from a Phoenix channel operation.
 */
export interface PhoenixReply {
  status: string;
  response: Record<string, unknown>;
}

/**
 * Event handler callback type.
 */
export type EventHandler = (payload: Record<string, unknown>) => void;

/**
 * Socket event callbacks.
 */
export interface SocketCallbacks {
  onOpen?: () => void;
  onClose?: (reason: string) => void;
  onError?: (error: Error) => void;
}

/**
 * Detects if running in Node.js environment.
 */
function isNode(): boolean {
  return (
    typeof process !== "undefined" && process.versions != null && process.versions.node != null
  );
}

/**
 * Gets the appropriate WebSocket constructor for the environment.
 */
async function getWebSocket(): Promise<typeof WebSocket> {
  if (typeof WebSocket !== "undefined") {
    return WebSocket;
  }

  if (isNode()) {
    // Dynamic import for Node.js WebSocket
    const ws = await import("ws");
    return ws.default as unknown as typeof WebSocket;
  }

  throw new Error("WebSocket is not available in this environment");
}

/**
 * Phoenix WebSocket client.
 *
 * Implements the Phoenix socket protocol for real-time communication
 * with Phoenix Framework servers.
 *
 * @example
 * ```typescript
 * const socket = new PhoenixSocket("wss://example.com/socket/websocket");
 * await socket.connect();
 *
 * socket.on("my_topic", "my_event", (payload) => {
 *   console.log("Received:", payload);
 * });
 * ```
 */
export class PhoenixSocket {
  private readonly url: string;
  private readonly heartbeatIntervalMs: number;
  private ws: WebSocket | null = null;
  private refCounter = 0;
  private pendingReplies: Map<
    string,
    {
      resolve: (reply: PhoenixReply) => void;
      reject: (error: Error) => void;
    }
  > = new Map();
  private eventHandlers: Map<string, EventHandler[]> = new Map();
  private _isConnected = false;
  private heartbeatTimer: ReturnType<typeof setInterval> | null = null;
  private callbacks: SocketCallbacks = {};

  /**
   * Creates a new Phoenix socket.
   *
   * @param url - WebSocket URL (e.g., wss://example.com/socket/websocket)
   * @param heartbeatIntervalMs - Heartbeat interval in milliseconds (default: 30000)
   */
  constructor(url: string, heartbeatIntervalMs = 30000) {
    this.url = url;
    this.heartbeatIntervalMs = heartbeatIntervalMs;
  }

  /**
   * Returns whether the socket is currently connected.
   */
  get isConnected(): boolean {
    return this._isConnected && this.ws?.readyState === WebSocket.OPEN;
  }

  /**
   * Sets the socket event callbacks.
   */
  setCallbacks(callbacks: SocketCallbacks): void {
    this.callbacks = callbacks;
  }

  /**
   * Connects to the Phoenix server.
   */
  async connect(): Promise<void> {
    const WebSocketImpl = await getWebSocket();

    return new Promise((resolve, reject) => {
      try {
        this.ws = new WebSocketImpl(this.url);

        this.ws.onopen = (): void => {
          this._isConnected = true;
          this.startHeartbeat();
          this.callbacks.onOpen?.();
          resolve();
        };

        this.ws.onclose = (event): void => {
          this._isConnected = false;
          this.stopHeartbeat();
          const reason = event.reason || "Connection closed";
          this.callbacks.onClose?.(reason);
        };

        this.ws.onerror = (event): void => {
          const error = new ConnectionError(`WebSocket error: ${event.type}`);
          this.callbacks.onError?.(error);
          if (!this._isConnected) {
            reject(error);
          }
        };

        this.ws.onmessage = (event): void => {
          this.handleMessage(event.data as string);
        };
      } catch (error) {
        reject(
          new ConnectionError(
            `Failed to connect to ${this.url}`,
            error instanceof Error ? error : undefined
          )
        );
      }
    });
  }

  /**
   * Disconnects from the Phoenix server.
   */
  async disconnect(): Promise<void> {
    this._isConnected = false;
    this.stopHeartbeat();

    // Reject all pending replies
    for (const [ref, pending] of this.pendingReplies) {
      pending.reject(new ConnectionError("Socket disconnected"));
      this.pendingReplies.delete(ref);
    }

    if (this.ws) {
      this.ws.close(1000, "Client disconnect");
      this.ws = null;
    }
  }

  /**
   * Sends a message and waits for a reply.
   *
   * @param topic - The channel topic
   * @param event - The event name
   * @param payload - The message payload
   * @param timeoutMs - Timeout in milliseconds (default: 10000)
   * @returns The reply from the server
   */
  async send(
    topic: string,
    event: string,
    payload: unknown,
    timeoutMs = 10000
  ): Promise<PhoenixReply> {
    const ref = this.generateRef();

    const message: PhoenixMessage = {
      topic,
      event,
      payload,
      ref,
    };

    return new Promise((resolve, reject) => {
      // Set up timeout
      const timeoutId = setTimeout(() => {
        this.pendingReplies.delete(ref);
        reject(new TimeoutError(timeoutMs));
      }, timeoutMs);

      // Store pending reply handler
      this.pendingReplies.set(ref, {
        resolve: (reply) => {
          clearTimeout(timeoutId);
          this.pendingReplies.delete(ref);
          resolve(reply);
        },
        reject: (error) => {
          clearTimeout(timeoutId);
          this.pendingReplies.delete(ref);
          reject(error);
        },
      });

      // Send the message
      this.sendRaw(JSON.stringify(message)).catch((error) => {
        clearTimeout(timeoutId);
        this.pendingReplies.delete(ref);
        reject(error);
      });
    });
  }

  /**
   * Sends a message without waiting for a reply.
   *
   * @param topic - The channel topic
   * @param event - The event name
   * @param payload - The message payload
   */
  async sendNoReply(topic: string, event: string, payload: unknown): Promise<void> {
    const ref = this.generateRef();

    const message: PhoenixMessage = {
      topic,
      event,
      payload,
      ref,
    };

    await this.sendRaw(JSON.stringify(message));
  }

  /**
   * Registers an event handler.
   *
   * @param topic - The channel topic
   * @param event - The event name
   * @param handler - The callback function
   */
  on(topic: string, event: string, handler: EventHandler): void {
    const key = `${topic}:${event}`;
    const handlers = this.eventHandlers.get(key) ?? [];
    handlers.push(handler);
    this.eventHandlers.set(key, handlers);
  }

  /**
   * Removes an event handler.
   *
   * @param topic - The channel topic
   * @param event - The event name
   * @param handler - The specific handler to remove, or undefined to remove all
   */
  off(topic: string, event: string, handler?: EventHandler): void {
    const key = `${topic}:${event}`;

    if (handler === undefined) {
      this.eventHandlers.delete(key);
    } else {
      const handlers = this.eventHandlers.get(key);
      if (handlers) {
        const index = handlers.indexOf(handler);
        if (index !== -1) {
          handlers.splice(index, 1);
        }
        if (handlers.length === 0) {
          this.eventHandlers.delete(key);
        }
      }
    }
  }

  /**
   * Removes all event handlers for a topic.
   */
  offAll(topic: string): void {
    for (const key of this.eventHandlers.keys()) {
      if (key.startsWith(`${topic}:`)) {
        this.eventHandlers.delete(key);
      }
    }
  }

  private async sendRaw(data: string): Promise<void> {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
      throw new ConnectionError("Socket is not connected");
    }

    this.ws.send(data);
  }

  private generateRef(): string {
    this.refCounter += 1;
    return String(this.refCounter);
  }

  private handleMessage(data: string): void {
    try {
      const message = JSON.parse(data) as PhoenixMessage;

      // Handle reply
      if (message.event === "phx_reply" && message.ref) {
        const pending = this.pendingReplies.get(message.ref);
        if (pending) {
          const payload = message.payload as Record<string, unknown>;
          const reply: PhoenixReply = {
            status: (payload["status"] as string) ?? "error",
            response: (payload["response"] as Record<string, unknown>) ?? {},
          };
          pending.resolve(reply);
        }
        return;
      }

      // Dispatch to event handlers
      const key = `${message.topic}:${message.event}`;
      const handlers = this.eventHandlers.get(key);
      if (handlers) {
        const payload = (message.payload as Record<string, unknown>) ?? {};
        for (const handler of handlers) {
          try {
            handler(payload);
          } catch (error) {
            console.error(`Error in event handler for ${key}:`, error);
          }
        }
      }
    } catch (error) {
      console.error("Failed to parse Phoenix message:", error);
    }
  }

  private startHeartbeat(): void {
    this.stopHeartbeat();

    this.heartbeatTimer = setInterval(() => {
      if (this.isConnected) {
        this.sendNoReply("phoenix", "heartbeat", {}).catch((error) => {
          console.warn("Failed to send heartbeat:", error);
        });
      }
    }, this.heartbeatIntervalMs);
  }

  private stopHeartbeat(): void {
    if (this.heartbeatTimer) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = null;
    }
  }
}
