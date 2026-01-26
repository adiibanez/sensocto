/**
 * Sensor stream implementation for sending sensor data.
 * @module sensor
 */

import { PhoenixChannel } from "./channel.js";
import { DisconnectedError, InvalidAttributeIdError } from "./errors.js";
import {
  type BackpressureConfig,
  type Measurement,
  defaultBackpressureConfig,
  parseBackpressureConfig,
} from "./models.js";

/**
 * Regex pattern for validating attribute IDs.
 * Must start with a letter and contain only alphanumeric characters, underscores, or hyphens.
 */
const ATTRIBUTE_ID_PATTERN = /^[a-zA-Z][a-zA-Z0-9_-]{0,63}$/;

/**
 * Validates an attribute ID.
 *
 * @param attributeId - The attribute ID to validate
 * @throws {InvalidAttributeIdError} If the attribute ID is invalid
 */
function validateAttributeId(attributeId: string): void {
  if (!attributeId) {
    throw new InvalidAttributeIdError(attributeId, "Attribute ID cannot be empty");
  }
  if (attributeId.length > 64) {
    throw new InvalidAttributeIdError(attributeId, "Attribute ID cannot exceed 64 characters");
  }
  if (!ATTRIBUTE_ID_PATTERN.test(attributeId)) {
    throw new InvalidAttributeIdError(
      attributeId,
      "Attribute ID must start with a letter and contain only alphanumeric characters, underscores, or hyphens"
    );
  }
}

/**
 * Configuration for a sensor.
 */
export interface SensorConfig {
  /** Human-readable name for the sensor. */
  sensorName: string;
  /** Unique sensor identifier (auto-generated if not provided). */
  sensorId?: string;
  /** Type of sensor. */
  sensorType?: string;
  /** List of attributes this sensor will report. */
  attributes?: string[];
  /** Sampling rate in Hz. */
  samplingRateHz?: number;
  /** Number of measurements to batch. */
  batchSize?: number;
}

/**
 * Callback for backpressure configuration updates.
 */
export type BackpressureHandler = (config: BackpressureConfig) => void;

/**
 * Stream for sending sensor measurements to the server.
 *
 * Supports both individual measurements and batched sending with
 * automatic backpressure handling based on server feedback.
 *
 * @example
 * ```typescript
 * const sensor = await client.registerSensor({
 *   sensorName: "Temperature Sensor",
 *   sensorType: "temperature",
 *   attributes: ["celsius", "fahrenheit"],
 * });
 *
 * // Send individual measurement
 * await sensor.sendMeasurement("celsius", { value: 23.5 });
 *
 * // Or use batching
 * await sensor.addToBatch("celsius", { value: 23.6 });
 * await sensor.addToBatch("celsius", { value: 23.7 });
 * await sensor.flushBatch();
 *
 * // Handle backpressure
 * sensor.onBackpressure((config) => {
 *   console.log("Backpressure:", config.attentionLevel);
 * });
 * ```
 */
export class SensorStream {
  private readonly channel: PhoenixChannel;
  private readonly _sensorId: string;
  private readonly _config: SensorConfig;
  private batchBuffer: Measurement[] = [];
  private _backpressure: BackpressureConfig;
  private backpressureHandler: BackpressureHandler | null = null;
  private unsubscribeBackpressure: (() => void) | null = null;

  /**
   * Creates a new sensor stream.
   *
   * @param channel - The Phoenix channel for this sensor
   * @param sensorId - The sensor ID
   * @param config - The sensor configuration
   */
  constructor(channel: PhoenixChannel, sensorId: string, config: SensorConfig) {
    this.channel = channel;
    this._sensorId = sensorId;
    this._config = config;
    this._backpressure = defaultBackpressureConfig();

    // Register backpressure handler
    this.unsubscribeBackpressure = this.channel.on(
      "backpressure_config",
      this.handleBackpressure.bind(this)
    );
  }

  /**
   * Returns the sensor ID.
   */
  get sensorId(): string {
    return this._sensorId;
  }

  /**
   * Returns the sensor configuration.
   */
  get config(): SensorConfig {
    return this._config;
  }

  /**
   * Returns whether the stream is active.
   */
  get isActive(): boolean {
    return this.channel.isJoined;
  }

  /**
   * Returns the current backpressure configuration.
   */
  get backpressureConfig(): BackpressureConfig {
    return this._backpressure;
  }

  /**
   * Returns whether sending is paused due to server backpressure.
   * When paused, measurements should not be sent to avoid overwhelming the server.
   */
  get isPaused(): boolean {
    return this._backpressure.paused;
  }

  /**
   * Sets the backpressure update handler.
   *
   * @param handler - Callback function called when backpressure config updates
   */
  onBackpressure(handler: BackpressureHandler): void {
    this.backpressureHandler = handler;
  }

  /**
   * Sends a single measurement to the server.
   *
   * @param attributeId - The attribute identifier
   * @param payload - The measurement payload
   * @param timestamp - Optional timestamp in milliseconds (uses current time if not provided)
   * @returns true if sent, false if skipped due to backpressure pause
   * @throws {DisconnectedError} If not connected
   * @throws {InvalidAttributeIdError} If attribute ID is invalid
   */
  async sendMeasurement(
    attributeId: string,
    payload: Record<string, unknown> | number | number[],
    timestamp?: number
  ): Promise<boolean> {
    if (!this.isActive) {
      throw new DisconnectedError();
    }

    // Skip sending when server signals pause (critical load + low attention)
    if (this._backpressure.paused) {
      return false;
    }

    validateAttributeId(attributeId);

    const message = {
      attribute_id: attributeId,
      payload,
      timestamp: timestamp ?? Date.now(),
    };

    await this.channel.pushNoReply("measurement", message);
    return true;
  }

  /**
   * Adds a measurement to the batch buffer.
   *
   * The batch will be sent when it reaches the recommended batch size
   * (based on backpressure) or when flushBatch() is called.
   * When server signals pause, measurements are still buffered but not sent.
   *
   * @param attributeId - The attribute identifier
   * @param payload - The measurement payload
   * @param timestamp - Optional timestamp in milliseconds
   * @throws {DisconnectedError} If not connected
   * @throws {InvalidAttributeIdError} If attribute ID is invalid
   */
  async addToBatch(
    attributeId: string,
    payload: Record<string, unknown> | number | number[],
    timestamp?: number
  ): Promise<void> {
    if (!this.isActive) {
      throw new DisconnectedError();
    }

    validateAttributeId(attributeId);

    const measurement: Measurement = {
      attributeId,
      payload,
      timestamp: timestamp ?? Date.now(),
    };

    this.batchBuffer.push(measurement);

    // Skip auto-flush when paused (measurements buffer but don't send)
    if (this._backpressure.paused) {
      return;
    }

    // Auto-flush if batch size reached
    if (this.batchBuffer.length >= this._backpressure.recommendedBatchSize) {
      await this.flushBatch();
    }
  }

  /**
   * Flushes any pending measurements in the batch buffer.
   * When server signals pause, flush is skipped and measurements remain buffered.
   *
   * @param force - If true, flush even when paused (use for close() cleanup)
   * @returns true if flushed, false if skipped due to pause or empty buffer
   */
  async flushBatch(force = false): Promise<boolean> {
    if (this.batchBuffer.length === 0) {
      return false;
    }

    // Skip flush when paused unless forced
    if (this._backpressure.paused && !force) {
      return false;
    }

    const measurements = this.batchBuffer.map((m) => ({
      attribute_id: m.attributeId,
      payload: m.payload,
      timestamp: m.timestamp,
    }));

    this.batchBuffer = [];

    await this.channel.pushNoReply("measurements_batch", measurements);
    return true;
  }

  /**
   * Updates the attribute registry.
   *
   * @param action - The action to perform ("add", "remove", "update")
   * @param attributeId - The attribute identifier
   * @param metadata - Optional metadata for the attribute
   * @throws {DisconnectedError} If not connected
   * @throws {InvalidAttributeIdError} If attribute ID is invalid
   */
  async updateAttribute(
    action: "add" | "remove" | "update",
    attributeId: string,
    metadata?: Record<string, unknown>
  ): Promise<void> {
    if (!this.isActive) {
      throw new DisconnectedError();
    }

    validateAttributeId(attributeId);

    const payload = {
      action,
      attribute_id: attributeId,
      metadata: metadata ?? {},
    };

    await this.channel.pushNoReply("update_attributes", payload);
  }

  /**
   * Closes the sensor stream.
   */
  async close(): Promise<void> {
    // Force flush remaining measurements even if paused
    await this.flushBatch(true);

    // Unsubscribe from backpressure events
    if (this.unsubscribeBackpressure) {
      this.unsubscribeBackpressure();
      this.unsubscribeBackpressure = null;
    }

    // Leave the channel
    await this.channel.leave();
  }

  private handleBackpressure(payload: Record<string, unknown>): void {
    this._backpressure = parseBackpressureConfig(payload);

    if (this.backpressureHandler) {
      try {
        this.backpressureHandler(this._backpressure);
      } catch (error) {
        console.error("Error in backpressure handler:", error);
      }
    }
  }
}
