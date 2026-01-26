/**
 * Phoenix Channel implementation for TypeScript.
 * @module channel
 */

import { ChannelError, ChannelJoinError } from "./errors.js";
import { ChannelState } from "./models.js";
import { type EventHandler, type PhoenixReply, PhoenixSocket } from "./socket.js";

/**
 * Represents a Phoenix channel for topic-based communication.
 *
 * @example
 * ```typescript
 * const channel = new PhoenixChannel(socket, "room:lobby", { user_id: "123" });
 * await channel.join();
 *
 * channel.on("new_message", (payload) => {
 *   console.log("New message:", payload);
 * });
 *
 * await channel.push("send_message", { body: "Hello!" });
 * ```
 */
export class PhoenixChannel {
  private readonly socket: PhoenixSocket;
  private readonly _topic: string;
  private readonly joinParams: Record<string, unknown>;
  private readonly eventHandlers: Map<string, EventHandler[]> = new Map();
  private _state: ChannelState = ChannelState.Closed;
  private joinResponse: Record<string, unknown> | null = null;

  /**
   * Creates a new Phoenix channel.
   *
   * @param socket - The Phoenix socket
   * @param topic - The channel topic
   * @param joinParams - Parameters to send when joining
   */
  constructor(socket: PhoenixSocket, topic: string, joinParams: Record<string, unknown> = {}) {
    this.socket = socket;
    this._topic = topic;
    this.joinParams = joinParams;
  }

  /**
   * The channel topic.
   */
  get topic(): string {
    return this._topic;
  }

  /**
   * Current state of the channel.
   */
  get state(): ChannelState {
    return this._state;
  }

  /**
   * Whether the channel is currently joined.
   */
  get isJoined(): boolean {
    return this._state === ChannelState.Joined;
  }

  /**
   * The response received when joining the channel.
   */
  get joinResponseData(): Record<string, unknown> | null {
    return this.joinResponse;
  }

  /**
   * Joins the channel.
   *
   * @returns The join response from the server
   * @throws {ChannelJoinError} If joining fails
   */
  async join(): Promise<PhoenixReply> {
    if (this._state === ChannelState.Joined) {
      return { status: "ok", response: this.joinResponse ?? {} };
    }

    this._state = ChannelState.Joining;

    try {
      const reply = await this.socket.send(this._topic, "phx_join", this.joinParams);

      if (reply.status === "ok") {
        this._state = ChannelState.Joined;
        this.joinResponse = reply.response;
      } else {
        this._state = ChannelState.Errored;
        const reason = (reply.response["reason"] as string) ?? JSON.stringify(reply.response);
        throw new ChannelJoinError(this._topic, reason);
      }

      return reply;
    } catch (error) {
      this._state = ChannelState.Errored;

      if (error instanceof ChannelJoinError) {
        throw error;
      }

      throw new ChannelJoinError(
        this._topic,
        error instanceof Error ? error.message : "Unknown error"
      );
    }
  }

  /**
   * Leaves the channel.
   */
  async leave(): Promise<void> {
    if (this._state !== ChannelState.Joined) {
      return;
    }

    this._state = ChannelState.Leaving;

    try {
      await this.socket.send(this._topic, "phx_leave", {});
    } finally {
      this._state = ChannelState.Closed;
      this.socket.offAll(this._topic);
      this.eventHandlers.clear();
    }
  }

  /**
   * Pushes a message to the channel and waits for a reply.
   *
   * @param event - The event name
   * @param payload - The message payload
   * @param timeoutMs - Timeout in milliseconds
   * @returns The response from the server
   * @throws {ChannelError} If the channel is not joined
   */
  async push(
    event: string,
    payload: Record<string, unknown> | unknown[],
    timeoutMs = 10000
  ): Promise<PhoenixReply> {
    if (this._state !== ChannelState.Joined) {
      throw new ChannelError(this._topic, "Channel is not joined");
    }

    return this.socket.send(this._topic, event, payload, timeoutMs);
  }

  /**
   * Pushes a message to the channel without waiting for a reply.
   *
   * @param event - The event name
   * @param payload - The message payload
   * @throws {ChannelError} If the channel is not joined
   */
  async pushNoReply(event: string, payload: Record<string, unknown> | unknown[]): Promise<void> {
    if (this._state !== ChannelState.Joined) {
      throw new ChannelError(this._topic, "Channel is not joined");
    }

    await this.socket.sendNoReply(this._topic, event, payload);
  }

  /**
   * Registers an event handler for the specified event.
   *
   * @param event - The event name to listen for
   * @param handler - The handler to invoke when the event is received
   * @returns A function to unsubscribe the handler
   */
  on(event: string, handler: EventHandler): () => void {
    // Register with socket
    this.socket.on(this._topic, event, handler);

    // Track locally for cleanup
    const handlers = this.eventHandlers.get(event) ?? [];
    handlers.push(handler);
    this.eventHandlers.set(event, handlers);

    // Return unsubscribe function
    return () => {
      this.off(event, handler);
    };
  }

  /**
   * Removes an event handler for the specified event.
   *
   * @param event - The event name
   * @param handler - The handler to remove
   */
  off(event: string, handler: EventHandler): void {
    this.socket.off(this._topic, event, handler);

    const handlers = this.eventHandlers.get(event);
    if (handlers) {
      const index = handlers.indexOf(handler);
      if (index !== -1) {
        handlers.splice(index, 1);
      }
      if (handlers.length === 0) {
        this.eventHandlers.delete(event);
      }
    }
  }

  /**
   * Removes all event handlers for the specified event.
   *
   * @param event - The event name
   */
  offAll(event: string): void {
    this.socket.off(this._topic, event);
    this.eventHandlers.delete(event);
  }
}
