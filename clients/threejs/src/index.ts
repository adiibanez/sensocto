/**
 * Sensocto TypeScript/Three.js SDK
 *
 * TypeScript client library for connecting to the Sensocto sensor platform.
 * Supports real-time sensor data streaming, video/voice calls, and room management.
 *
 * @packageDocumentation
 *
 * @example Basic Usage
 * ```typescript
 * import { SensoctoClient, SensorConfig } from "@sensocto/threejs";
 *
 * // Create client
 * const client = new SensoctoClient({
 *   serverUrl: "https://your-server.com",
 *   bearerToken: "your-token",
 *   connectorName: "My Sensor Hub",
 * });
 *
 * // Connect
 * await client.connect();
 *
 * // Register a sensor
 * const sensor = await client.registerSensor({
 *   sensorName: "Temperature Sensor",
 *   sensorType: "temperature",
 *   attributes: ["celsius", "fahrenheit"],
 * });
 *
 * // Send measurements
 * await sensor.sendMeasurement("celsius", { value: 23.5 });
 *
 * // Or use batch sending
 * await sensor.addToBatch("celsius", { value: 23.6 });
 * await sensor.addToBatch("celsius", { value: 23.7 });
 * await sensor.flushBatch();
 *
 * // Cleanup
 * await client.disconnect();
 * ```
 *
 * @example Three.js Integration
 * ```typescript
 * import { SensoctoClient } from "@sensocto/threejs";
 * import { SensorObject3D, SensorDataVisualizer } from "@sensocto/threejs/three";
 * import * as THREE from "three";
 *
 * // Create scene and sensor visualization
 * const scene = new THREE.Scene();
 * const sensorObject = new SensorObject3D();
 * scene.add(sensorObject);
 *
 * // Bind sensor data to 3D object
 * sensor.onBackpressure((config) => {
 *   sensorObject.setAttentionLevel(config.attentionLevel);
 * });
 * ```
 *
 * @module @sensocto/threejs
 */

// Main client
export { SensoctoClient } from "./client.js";
export type { BackpressureConfigHandler, ConnectionStateHandler, ErrorHandler } from "./client.js";

// Configuration
export type { SensoctoConfig } from "./config.js";
export { DEFAULT_CONFIG, resolveConfig, validateConfig } from "./config.js";

// Sensor streaming
export { SensorStream } from "./sensor.js";
export type { BackpressureHandler, SensorConfig } from "./sensor.js";

// Call sessions
export { CallSession } from "./call.js";
export type { CallEventHandler } from "./call.js";

// Phoenix protocol
export { PhoenixChannel } from "./channel.js";
export { PhoenixSocket } from "./socket.js";
export type { EventHandler, PhoenixMessage, PhoenixReply, SocketCallbacks } from "./socket.js";

// Models
export {
  AttentionLevel,
  ChannelState,
  ConnectionState,
  RoomRole,
  createMeasurement,
  defaultBackpressureConfig,
  getRecommendedBatchSize,
  getRecommendedBatchWindow,
  parseBackpressureConfig,
} from "./models.js";
export type {
  AnyCallEvent,
  BackpressureConfig,
  BackpressureConfigEvent,
  CallEndedEvent,
  CallEvent,
  CallParticipant,
  GenericSensorEvent,
  IceServer,
  Measurement,
  MediaEventReceived,
  ParticipantAudioChangedEvent,
  ParticipantJoinedEvent,
  ParticipantLeftEvent,
  ParticipantVideoChangedEvent,
  QualityChangedEvent,
  Room,
  SensorEvent,
  User,
} from "./models.js";

// Errors
export {
  AuthenticationError,
  ChannelError,
  ChannelJoinError,
  ConnectionError,
  DisconnectedError,
  InvalidAttributeIdError,
  InvalidConfigError,
  SensoctoError,
  TimeoutError,
} from "./errors.js";

/**
 * Package version.
 */
export const VERSION = "0.1.0";
