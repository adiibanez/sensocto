/**
 * Data models for the Sensocto client.
 * @module models
 */

/**
 * Connection state of the client.
 */
export enum ConnectionState {
  /** Client is not connected. */
  Disconnected = "disconnected",
  /** Client is attempting to connect. */
  Connecting = "connecting",
  /** Client is connected. */
  Connected = "connected",
  /** Client is attempting to reconnect. */
  Reconnecting = "reconnecting",
  /** Client encountered an error. */
  Error = "error",
}

/**
 * Server attention level for backpressure control.
 */
export enum AttentionLevel {
  /** No backpressure. */
  None = "none",
  /** Low attention level. */
  Low = "low",
  /** Medium attention level. */
  Medium = "medium",
  /** High attention level - slow down sending. */
  High = "high",
}

/**
 * System load level from the server.
 */
export enum SystemLoadLevel {
  /** System running smoothly. */
  Normal = "normal",
  /** Moderate load. */
  Elevated = "elevated",
  /** Heavy load. */
  High = "high",
  /** System overloaded. */
  Critical = "critical",
}

/**
 * Returns the recommended batch window in milliseconds for an attention level.
 */
export function getRecommendedBatchWindow(level: AttentionLevel): number {
  const windows: Record<AttentionLevel, number> = {
    [AttentionLevel.High]: 100,
    [AttentionLevel.Medium]: 500,
    [AttentionLevel.Low]: 2000,
    [AttentionLevel.None]: 5000,
  };
  return windows[level];
}

/**
 * Returns the recommended batch size for an attention level.
 */
export function getRecommendedBatchSize(level: AttentionLevel): number {
  const sizes: Record<AttentionLevel, number> = {
    [AttentionLevel.High]: 1,
    [AttentionLevel.Medium]: 5,
    [AttentionLevel.Low]: 10,
    [AttentionLevel.None]: 20,
  };
  return sizes[level];
}

/**
 * Room membership role.
 */
export enum RoomRole {
  Owner = "owner",
  Admin = "admin",
  Member = "member",
}

/**
 * State of a Phoenix channel.
 */
export enum ChannelState {
  Closed = "closed",
  Joining = "joining",
  Joined = "joined",
  Leaving = "leaving",
  Errored = "errored",
}

/**
 * A single sensor measurement.
 */
export interface Measurement {
  /** The attribute identifier. */
  attributeId: string;
  /** The measurement payload. */
  payload: Record<string, unknown> | number | number[];
  /** Unix timestamp in milliseconds. */
  timestamp: number;
}

/**
 * Creates a measurement with an auto-generated timestamp if not provided.
 */
export function createMeasurement(
  attributeId: string,
  payload: Record<string, unknown> | number | number[],
  timestamp?: number
): Measurement {
  return {
    attributeId,
    payload,
    timestamp: timestamp ?? Date.now(),
  };
}

/**
 * Backpressure configuration from the server.
 */
export interface BackpressureConfig {
  /** The current attention level. */
  attentionLevel: AttentionLevel;
  /** Current system load level. */
  systemLoad: SystemLoadLevel;
  /** Whether the client should pause sending data. */
  paused: boolean;
  /** Recommended batch window in milliseconds. */
  recommendedBatchWindow: number;
  /** Recommended batch size. */
  recommendedBatchSize: number;
  /** Load multiplier applied to batch window. */
  loadMultiplier: number;
  /** Server timestamp. */
  timestamp: number;
}

/**
 * Creates a BackpressureConfig from a server payload.
 */
export function parseBackpressureConfig(payload: Record<string, unknown>): BackpressureConfig {
  const attention = (payload["attention_level"] as string) ?? "none";
  let attentionLevel: AttentionLevel;

  switch (attention) {
    case "high":
      attentionLevel = AttentionLevel.High;
      break;
    case "medium":
      attentionLevel = AttentionLevel.Medium;
      break;
    case "low":
      attentionLevel = AttentionLevel.Low;
      break;
    default:
      attentionLevel = AttentionLevel.None;
  }

  const load = (payload["system_load"] as string) ?? "normal";
  let systemLoad: SystemLoadLevel;

  switch (load) {
    case "critical":
      systemLoad = SystemLoadLevel.Critical;
      break;
    case "high":
      systemLoad = SystemLoadLevel.High;
      break;
    case "elevated":
      systemLoad = SystemLoadLevel.Elevated;
      break;
    default:
      systemLoad = SystemLoadLevel.Normal;
  }

  return {
    attentionLevel,
    systemLoad,
    paused: (payload["paused"] as boolean) ?? false,
    recommendedBatchWindow: (payload["recommended_batch_window"] as number) ?? 500,
    recommendedBatchSize: (payload["recommended_batch_size"] as number) ?? 5,
    loadMultiplier: (payload["load_multiplier"] as number) ?? 1.0,
    timestamp: (payload["timestamp"] as number) ?? 0,
  };
}

/**
 * Default backpressure configuration.
 */
export function defaultBackpressureConfig(): BackpressureConfig {
  return {
    attentionLevel: AttentionLevel.None,
    systemLoad: SystemLoadLevel.Normal,
    paused: false,
    recommendedBatchWindow: 500,
    recommendedBatchSize: 5,
    loadMultiplier: 1.0,
    timestamp: 0,
  };
}

/**
 * Returns the effective batch window considering load multiplier.
 */
export function getEffectiveBatchWindow(config: BackpressureConfig): number {
  return Math.round(config.recommendedBatchWindow * config.loadMultiplier);
}

/**
 * A room in Sensocto.
 */
export interface Room {
  id: string;
  name: string;
  description?: string;
  joinCode?: string;
  isPublic: boolean;
  callsEnabled: boolean;
  ownerId: string;
  configuration: Record<string, unknown>;
}

/**
 * A user in Sensocto.
 */
export interface User {
  id: string;
  email?: string;
}

/**
 * A call participant.
 */
export interface CallParticipant {
  userId: string;
  endpointId: string;
  userInfo: Record<string, unknown>;
  joinedAt?: string;
  audioEnabled: boolean;
  videoEnabled: boolean;
}

/**
 * ICE server configuration for WebRTC.
 */
export interface IceServer {
  urls: string[];
  username?: string;
  credential?: string;
}

// ============================================================================
// Event Types
// ============================================================================

/**
 * Base interface for sensor events.
 */
export interface SensorEvent {
  type: string;
}

/**
 * Backpressure configuration update event.
 */
export interface BackpressureConfigEvent extends SensorEvent {
  type: "backpressure_config";
  config: BackpressureConfig;
}

/**
 * Generic sensor event with payload.
 */
export interface GenericSensorEvent extends SensorEvent {
  type: "generic";
  event: string;
  payload: Record<string, unknown>;
}

/**
 * Base interface for call events.
 */
export interface CallEvent {
  type: string;
}

/**
 * Event when a participant joins.
 */
export interface ParticipantJoinedEvent extends CallEvent {
  type: "participant_joined";
  participant: CallParticipant;
}

/**
 * Event when a participant leaves.
 */
export interface ParticipantLeftEvent extends CallEvent {
  type: "participant_left";
  userId: string;
  crashed: boolean;
}

/**
 * WebRTC media event received.
 */
export interface MediaEventReceived extends CallEvent {
  type: "media_event";
  data: unknown;
}

/**
 * Event when participant audio state changes.
 */
export interface ParticipantAudioChangedEvent extends CallEvent {
  type: "participant_audio_changed";
  userId: string;
  enabled: boolean;
}

/**
 * Event when participant video state changes.
 */
export interface ParticipantVideoChangedEvent extends CallEvent {
  type: "participant_video_changed";
  userId: string;
  enabled: boolean;
}

/**
 * Event when call quality changes.
 */
export interface QualityChangedEvent extends CallEvent {
  type: "quality_changed";
  quality: string;
}

/**
 * Event when call ends.
 */
export interface CallEndedEvent extends CallEvent {
  type: "call_ended";
}

/**
 * Union type of all call events.
 */
export type AnyCallEvent =
  | ParticipantJoinedEvent
  | ParticipantLeftEvent
  | MediaEventReceived
  | ParticipantAudioChangedEvent
  | ParticipantVideoChangedEvent
  | QualityChangedEvent
  | CallEndedEvent;
