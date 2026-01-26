/**
 * Configuration types for the Sensocto client.
 * @module config
 */

import { InvalidConfigError } from "./errors.js";

/**
 * Generates a UUID v4.
 */
function generateUUID(): string {
  // Use crypto.randomUUID if available (modern browsers and Node 19+)
  if (typeof crypto !== "undefined" && crypto.randomUUID) {
    return crypto.randomUUID();
  }

  // Fallback implementation
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === "x" ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}

/**
 * Configuration options for the Sensocto client.
 */
export interface SensoctoConfig {
  /** The Sensocto server URL (required). */
  serverUrl: string;
  /** Bearer token for authentication. */
  bearerToken?: string;
  /** Human-readable name for this connector. */
  connectorName?: string;
  /** Type of connector. */
  connectorType?: string;
  /** Unique connector identifier (auto-generated if not provided). */
  connectorId?: string;
  /** Automatically join connector channel on connect. */
  autoJoinConnector?: boolean;
  /** Heartbeat interval in milliseconds. */
  heartbeatIntervalMs?: number;
  /** Connection timeout in milliseconds. */
  connectionTimeoutMs?: number;
  /** Whether to auto-reconnect on disconnect. */
  autoReconnect?: boolean;
  /** Maximum reconnection attempts. */
  maxReconnectAttempts?: number;
  /** Supported features. */
  features?: string[];
}

/**
 * Default configuration values.
 */
export const DEFAULT_CONFIG: Required<Omit<SensoctoConfig, "serverUrl" | "bearerToken">> = {
  connectorName: "TypeScript Connector",
  connectorType: "typescript",
  connectorId: "",
  autoJoinConnector: true,
  heartbeatIntervalMs: 30000,
  connectionTimeoutMs: 10000,
  autoReconnect: true,
  maxReconnectAttempts: 5,
  features: [],
};

/**
 * Resolves configuration with defaults.
 */
export function resolveConfig(config: SensoctoConfig): Required<SensoctoConfig> {
  return {
    serverUrl: config.serverUrl,
    bearerToken: config.bearerToken ?? "",
    connectorName: config.connectorName ?? DEFAULT_CONFIG.connectorName,
    connectorType: config.connectorType ?? DEFAULT_CONFIG.connectorType,
    connectorId: config.connectorId ?? generateUUID(),
    autoJoinConnector: config.autoJoinConnector ?? DEFAULT_CONFIG.autoJoinConnector,
    heartbeatIntervalMs: config.heartbeatIntervalMs ?? DEFAULT_CONFIG.heartbeatIntervalMs,
    connectionTimeoutMs: config.connectionTimeoutMs ?? DEFAULT_CONFIG.connectionTimeoutMs,
    autoReconnect: config.autoReconnect ?? DEFAULT_CONFIG.autoReconnect,
    maxReconnectAttempts: config.maxReconnectAttempts ?? DEFAULT_CONFIG.maxReconnectAttempts,
    features: config.features ?? DEFAULT_CONFIG.features,
  };
}

/**
 * Validates a configuration object.
 *
 * @param config - The configuration to validate
 * @throws {InvalidConfigError} If the configuration is invalid
 */
export function validateConfig(config: SensoctoConfig): void {
  if (!config.serverUrl) {
    throw new InvalidConfigError("Server URL is required");
  }

  let url: URL;
  try {
    url = new URL(config.serverUrl);
  } catch {
    throw new InvalidConfigError("Server URL is not a valid URL");
  }

  if (!["http:", "https:"].includes(url.protocol)) {
    throw new InvalidConfigError("Server URL must use http or https scheme");
  }

  if (!url.hostname) {
    throw new InvalidConfigError("Server URL must have a host");
  }

  if (config.heartbeatIntervalMs !== undefined && config.heartbeatIntervalMs < 1000) {
    throw new InvalidConfigError("Heartbeat interval must be at least 1000ms");
  }
}

/**
 * Builds the WebSocket URL from the server URL.
 */
export function buildWebSocketUrl(serverUrl: string): string {
  const url = new URL(serverUrl);
  const protocol = url.protocol === "https:" ? "wss:" : "ws:";
  const port = url.port ? `:${url.port}` : "";
  return `${protocol}//${url.hostname}${port}/socket/websocket`;
}
