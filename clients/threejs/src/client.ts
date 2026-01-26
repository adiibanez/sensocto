/**
 * Main Sensocto client implementation.
 * @module client
 */

import { CallSession } from "./call.js";
import { PhoenixChannel } from "./channel.js";
import { buildWebSocketUrl, resolveConfig, type SensoctoConfig, validateConfig } from "./config.js";
import { DisconnectedError } from "./errors.js";
import { type BackpressureConfig, ConnectionState, type IceServer } from "./models.js";
import { type SensorConfig, SensorStream } from "./sensor.js";
import { PhoenixSocket } from "./socket.js";

/**
 * Generates a UUID v4.
 */
function generateUUID(): string {
  if (typeof crypto !== "undefined" && crypto.randomUUID) {
    return crypto.randomUUID();
  }
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === "x" ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}

/**
 * Connection state change callback.
 */
export type ConnectionStateHandler = (state: ConnectionState) => void;

/**
 * Backpressure configuration callback.
 */
export type BackpressureConfigHandler = (config: BackpressureConfig) => void;

/**
 * Error callback.
 */
export type ErrorHandler = (error: Error) => void;

/**
 * Reconnection event details.
 */
export interface ReconnectionEvent {
  attempt: number;
  maxAttempts: number;
  nextRetryMs: number;
}

/**
 * Reconnection event callback.
 */
export type ReconnectionHandler = (event: ReconnectionEvent) => void;

/**
 * Main client for connecting to Sensocto.
 *
 * Handles authentication, sensor management, real-time data streaming,
 * and video/voice calls through Phoenix WebSocket channels.
 *
 * @example
 * ```typescript
 * // Create and connect
 * const client = new SensoctoClient({
 *   serverUrl: "https://your-server.com",
 *   bearerToken: "your-token",
 *   connectorName: "My Sensor Hub",
 * });
 *
 * await client.connect();
 *
 * // Register a sensor
 * const sensor = await client.registerSensor({
 *   sensorName: "Temperature Sensor",
 *   sensorType: "temperature",
 *   attributes: ["celsius"],
 * });
 *
 * // Send measurements
 * await sensor.sendMeasurement("celsius", { value: 23.5 });
 *
 * // Cleanup
 * await client.disconnect();
 * ```
 *
 * @example
 * ```typescript
 * // Using async context manager pattern
 * const client = new SensoctoClient({ serverUrl: "..." });
 *
 * try {
 *   await client.connect();
 *   // ... use client
 * } finally {
 *   await client.disconnect();
 * }
 * ```
 */
export class SensoctoClient {
  private readonly config: Required<SensoctoConfig>;
  private socket: PhoenixSocket | null = null;
  private connectorChannel: PhoenixChannel | null = null;
  private _connectionState: ConnectionState = ConnectionState.Disconnected;

  // Event handlers
  private connectionStateHandlers: ConnectionStateHandler[] = [];
  private backpressureHandlers: BackpressureConfigHandler[] = [];
  private errorHandlers: ErrorHandler[] = [];
  private reconnectionHandlers: ReconnectionHandler[] = [];

  // Reconnection state
  private reconnectAttempt = 0;
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private stopReconnecting = false;
  private intentionalDisconnect = false;

  /**
   * Creates a new Sensocto client.
   *
   * @param config - Client configuration
   */
  constructor(config: SensoctoConfig) {
    validateConfig(config);
    this.config = resolveConfig(config);
  }

  /**
   * Returns the current connection state.
   */
  get connectionState(): ConnectionState {
    return this._connectionState;
  }

  /**
   * Returns whether the client is connected.
   */
  get isConnected(): boolean {
    return this._connectionState === ConnectionState.Connected;
  }

  /**
   * Returns the connector ID.
   */
  get connectorId(): string {
    return this.config.connectorId;
  }

  /**
   * Returns the connector name.
   */
  get connectorName(): string {
    return this.config.connectorName;
  }

  /**
   * Registers a connection state change handler.
   *
   * @param handler - Callback for state changes
   * @returns Unsubscribe function
   */
  onConnectionStateChange(handler: ConnectionStateHandler): () => void {
    this.connectionStateHandlers.push(handler);
    return () => {
      const index = this.connectionStateHandlers.indexOf(handler);
      if (index !== -1) {
        this.connectionStateHandlers.splice(index, 1);
      }
    };
  }

  /**
   * Registers a backpressure configuration handler.
   *
   * @param handler - Callback for backpressure updates
   * @returns Unsubscribe function
   */
  onBackpressureConfig(handler: BackpressureConfigHandler): () => void {
    this.backpressureHandlers.push(handler);
    return () => {
      const index = this.backpressureHandlers.indexOf(handler);
      if (index !== -1) {
        this.backpressureHandlers.splice(index, 1);
      }
    };
  }

  /**
   * Registers an error handler.
   *
   * @param handler - Callback for errors
   * @returns Unsubscribe function
   */
  onError(handler: ErrorHandler): () => void {
    this.errorHandlers.push(handler);
    return () => {
      const index = this.errorHandlers.indexOf(handler);
      if (index !== -1) {
        this.errorHandlers.splice(index, 1);
      }
    };
  }

  /**
   * Registers a reconnection event handler.
   *
   * @param handler - Callback for reconnection attempts
   * @returns Unsubscribe function
   */
  onReconnecting(handler: ReconnectionHandler): () => void {
    this.reconnectionHandlers.push(handler);
    return () => {
      const index = this.reconnectionHandlers.indexOf(handler);
      if (index !== -1) {
        this.reconnectionHandlers.splice(index, 1);
      }
    };
  }

  /**
   * Calculates exponential backoff delay with jitter.
   */
  private calculateBackoff(attempt: number): number {
    // Base delay: 1s, 2s, 4s, 8s, 16s, max 30s
    const baseMs = 1000 * Math.pow(2, attempt - 1);
    const cappedMs = Math.min(baseMs, 30000);

    // Add jitter (±20%)
    const jitterRange = cappedMs * 0.2;
    const jitter = Math.random() * jitterRange * 2 - jitterRange;
    return Math.round(cappedMs + jitter);
  }

  /**
   * Dispatches reconnection event to handlers.
   */
  private dispatchReconnecting(event: ReconnectionEvent): void {
    for (const handler of this.reconnectionHandlers) {
      try {
        handler(event);
      } catch (error) {
        console.error("Error in reconnection handler:", error);
      }
    }
  }

  /**
   * Attempts to reconnect after connection loss.
   */
  private async attemptReconnect(): Promise<void> {
    if (this.stopReconnecting || this.intentionalDisconnect) {
      return;
    }

    const maxAttempts = this.config.maxReconnectAttempts;

    while (this.reconnectAttempt < maxAttempts && !this.stopReconnecting) {
      this.reconnectAttempt++;
      const delay = this.calculateBackoff(this.reconnectAttempt);

      console.log(
        `[Sensocto] Reconnection attempt ${this.reconnectAttempt}/${maxAttempts} in ${delay}ms`
      );

      this.setConnectionState(ConnectionState.Reconnecting);
      this.dispatchReconnecting({
        attempt: this.reconnectAttempt,
        maxAttempts,
        nextRetryMs: delay,
      });

      // Wait before attempting
      await new Promise((resolve) => {
        this.reconnectTimer = setTimeout(resolve, delay);
      });

      if (this.stopReconnecting) {
        break;
      }

      try {
        await this.doConnect();
        console.log(`[Sensocto] Reconnected on attempt ${this.reconnectAttempt}`);
        this.reconnectAttempt = 0;
        return;
      } catch (error) {
        console.warn(`[Sensocto] Reconnection attempt ${this.reconnectAttempt} failed:`, error);
      }
    }

    if (!this.stopReconnecting && !this.intentionalDisconnect) {
      console.error(`[Sensocto] Failed to reconnect after ${maxAttempts} attempts`);
      this.setConnectionState(ConnectionState.Error);
      this.dispatchError(new Error(`Failed to reconnect after ${maxAttempts} attempts`));
    }
  }

  /**
   * Internal connect implementation.
   */
  private async doConnect(): Promise<void> {
    const wsUrl = buildWebSocketUrl(this.config.serverUrl);
    this.socket = new PhoenixSocket(wsUrl, this.config.heartbeatIntervalMs);

    this.socket.setCallbacks({
      onOpen: () => {
        console.log("[Sensocto] Socket opened");
      },
      onClose: (reason) => {
        console.log(`[Sensocto] Socket closed: ${reason}`);
        if (!this.intentionalDisconnect && this.config.autoReconnect) {
          this.attemptReconnect();
        } else {
          this.setConnectionState(ConnectionState.Disconnected);
        }
      },
      onError: (error) => {
        console.error("[Sensocto] Socket error:", error);
        this.dispatchError(error);
      },
    });

    await this.socket.connect();
    this.setConnectionState(ConnectionState.Connected);

    // Auto-join connector channel if configured
    if (this.config.autoJoinConnector) {
      await this.joinConnectorChannel();
    }
  }

  /**
   * Connects to the Sensocto server.
   */
  async connect(): Promise<void> {
    this.intentionalDisconnect = false;
    this.stopReconnecting = false;
    this.reconnectAttempt = 0;
    this.setConnectionState(ConnectionState.Connecting);

    try {
      await this.doConnect();
    } catch (error) {
      this.setConnectionState(ConnectionState.Error);
      throw error;
    }
  }

  /**
   * Connects with automatic retry on initial failure.
   * Uses exponential backoff with jitter.
   */
  async connectWithRetry(): Promise<void> {
    this.intentionalDisconnect = false;
    this.stopReconnecting = false;

    const maxAttempts = this.config.maxReconnectAttempts;

    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        this.setConnectionState(ConnectionState.Connecting);
        await this.doConnect();
        return;
      } catch (error) {
        if (attempt === maxAttempts) {
          this.setConnectionState(ConnectionState.Error);
          throw new Error(`Failed to connect after ${maxAttempts} attempts: ${error}`);
        }

        const delay = this.calculateBackoff(attempt);
        console.warn(`[Sensocto] Connection attempt ${attempt} failed. Retrying in ${delay}ms...`);
        this.dispatchReconnecting({
          attempt,
          maxAttempts,
          nextRetryMs: delay,
        });
        await new Promise((resolve) => setTimeout(resolve, delay));
      }
    }
  }

  /**
   * Disconnects from the Sensocto server.
   */
  async disconnect(): Promise<void> {
    // Stop any reconnection attempts
    this.intentionalDisconnect = true;
    this.stopReconnecting = true;
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }

    if (this.connectorChannel) {
      await this.connectorChannel.leave();
      this.connectorChannel = null;
    }

    if (this.socket) {
      await this.socket.disconnect();
      this.socket = null;
    }

    this.setConnectionState(ConnectionState.Disconnected);
  }

  /**
   * Registers a sensor and returns a stream for sending measurements.
   *
   * @param config - The sensor configuration
   * @returns A SensorStream for sending measurements
   * @throws {DisconnectedError} If not connected
   */
  async registerSensor(config: SensorConfig): Promise<SensorStream> {
    if (!this.isConnected || !this.socket) {
      throw new DisconnectedError();
    }

    const sensorId = config.sensorId ?? generateUUID();
    const topic = `sensocto:sensor:${sensorId}`;

    const joinParams = {
      connector_id: this.config.connectorId,
      connector_name: this.config.connectorName,
      sensor_id: sensorId,
      sensor_name: config.sensorName,
      sensor_type: config.sensorType ?? "generic",
      attributes: config.attributes ?? [],
      sampling_rate: config.samplingRateHz ?? 10,
      batch_size: config.batchSize ?? 5,
      bearer_token: this.config.bearerToken,
    };

    const channel = new PhoenixChannel(this.socket, topic, joinParams);
    await channel.join();

    const stream = new SensorStream(channel, sensorId, config);

    // Forward backpressure events
    stream.onBackpressure((bpConfig) => {
      for (const handler of this.backpressureHandlers) {
        try {
          handler(bpConfig);
        } catch (error) {
          console.error("Error in backpressure handler:", error);
        }
      }
    });

    return stream;
  }

  /**
   * Joins a video/voice call in a room.
   *
   * @param roomId - The room ID
   * @param userId - The user ID
   * @param userInfo - Optional additional user information
   * @returns A CallSession for managing the call
   * @throws {DisconnectedError} If not connected
   */
  async joinCall(
    roomId: string,
    userId: string,
    userInfo?: Record<string, unknown>
  ): Promise<CallSession> {
    if (!this.isConnected || !this.socket) {
      throw new DisconnectedError();
    }

    const topic = `call:${roomId}`;

    const joinParams = {
      user_id: userId,
      user_info: userInfo ?? {},
    };

    const channel = new PhoenixChannel(this.socket, topic, joinParams);
    await channel.join();

    // Extract ICE servers from join response
    const joinResponse = channel.joinResponseData ?? {};
    const rawIceServers = (joinResponse["ice_servers"] as unknown[]) ?? [];
    const iceServers: IceServer[] = rawIceServers.map((server) => {
      const s = server as Record<string, unknown>;
      const result: IceServer = {
        urls: (s["urls"] as string[]) ?? [],
      };
      if (typeof s["username"] === "string") {
        result.username = s["username"];
      }
      if (typeof s["credential"] === "string") {
        result.credential = s["credential"];
      }
      return result;
    });

    return new CallSession(channel, roomId, userId, iceServers);
  }

  private async joinConnectorChannel(): Promise<void> {
    if (!this.socket) {
      return;
    }

    const topic = `sensocto:connector:${this.config.connectorId}`;

    const joinParams = {
      connector_id: this.config.connectorId,
      connector_name: this.config.connectorName,
      connector_type: this.config.connectorType,
      features: this.config.features,
      bearer_token: this.config.bearerToken,
    };

    this.connectorChannel = new PhoenixChannel(this.socket, topic, joinParams);

    try {
      await this.connectorChannel.join();
      console.log("[Sensocto] Joined connector channel");
    } catch (error) {
      console.warn("[Sensocto] Failed to join connector channel:", error);
    }
  }

  private setConnectionState(state: ConnectionState): void {
    if (this._connectionState !== state) {
      this._connectionState = state;
      for (const handler of this.connectionStateHandlers) {
        try {
          handler(state);
        } catch (error) {
          console.error("Error in connection state handler:", error);
        }
      }
    }
  }

  private dispatchError(error: Error): void {
    for (const handler of this.errorHandlers) {
      try {
        handler(error);
      } catch (e) {
        console.error("Error in error handler:", e);
      }
    }
  }
}
