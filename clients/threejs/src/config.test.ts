import { describe, expect, it } from "vitest";

import { InvalidConfigError } from "./errors.js";
import { buildWebSocketUrl, DEFAULT_CONFIG, resolveConfig, validateConfig } from "./config.js";

describe("DEFAULT_CONFIG", () => {
  it("should have sensible defaults", () => {
    expect(DEFAULT_CONFIG.connectorName).toBe("TypeScript Connector");
    expect(DEFAULT_CONFIG.connectorType).toBe("typescript");
    expect(DEFAULT_CONFIG.autoJoinConnector).toBe(true);
    expect(DEFAULT_CONFIG.heartbeatIntervalMs).toBe(30000);
    expect(DEFAULT_CONFIG.connectionTimeoutMs).toBe(10000);
    expect(DEFAULT_CONFIG.autoReconnect).toBe(true);
    expect(DEFAULT_CONFIG.maxReconnectAttempts).toBe(5);
    expect(DEFAULT_CONFIG.features).toEqual([]);
  });
});

describe("resolveConfig", () => {
  it("should apply defaults for missing options", () => {
    const config = resolveConfig({ serverUrl: "https://example.com" });

    expect(config.serverUrl).toBe("https://example.com");
    expect(config.bearerToken).toBe("");
    expect(config.connectorName).toBe("TypeScript Connector");
    expect(config.connectorType).toBe("typescript");
    expect(config.autoJoinConnector).toBe(true);
    expect(config.heartbeatIntervalMs).toBe(30000);
  });

  it("should preserve provided options", () => {
    const config = resolveConfig({
      serverUrl: "https://example.com",
      bearerToken: "my-token",
      connectorName: "Custom Name",
      heartbeatIntervalMs: 15000,
    });

    expect(config.bearerToken).toBe("my-token");
    expect(config.connectorName).toBe("Custom Name");
    expect(config.heartbeatIntervalMs).toBe(15000);
  });

  it("should generate connector ID if not provided", () => {
    const config = resolveConfig({ serverUrl: "https://example.com" });
    expect(config.connectorId).toBeTruthy();
    expect(config.connectorId.length).toBeGreaterThan(0);
  });

  it("should use provided connector ID", () => {
    const config = resolveConfig({
      serverUrl: "https://example.com",
      connectorId: "my-connector-id",
    });
    expect(config.connectorId).toBe("my-connector-id");
  });
});

describe("validateConfig", () => {
  it("should throw if server URL is missing", () => {
    expect(() => validateConfig({ serverUrl: "" })).toThrow(InvalidConfigError);
    expect(() => validateConfig({ serverUrl: "" })).toThrow("Server URL is required");
  });

  it("should throw if server URL is invalid", () => {
    expect(() => validateConfig({ serverUrl: "not-a-url" })).toThrow(InvalidConfigError);
    expect(() => validateConfig({ serverUrl: "not-a-url" })).toThrow(
      "Server URL is not a valid URL"
    );
  });

  it("should throw if server URL has wrong protocol", () => {
    expect(() => validateConfig({ serverUrl: "ftp://example.com" })).toThrow(
      "Server URL must use http or https scheme"
    );
  });

  it("should throw if heartbeat interval is too low", () => {
    expect(() =>
      validateConfig({
        serverUrl: "https://example.com",
        heartbeatIntervalMs: 500,
      })
    ).toThrow("Heartbeat interval must be at least 1000ms");
  });

  it("should accept valid http URL", () => {
    expect(() => validateConfig({ serverUrl: "http://example.com" })).not.toThrow();
  });

  it("should accept valid https URL", () => {
    expect(() => validateConfig({ serverUrl: "https://example.com" })).not.toThrow();
  });

  it("should accept valid URL with port", () => {
    expect(() => validateConfig({ serverUrl: "https://example.com:4000" })).not.toThrow();
  });

  it("should accept valid URL with path", () => {
    expect(() => validateConfig({ serverUrl: "https://example.com/api" })).not.toThrow();
  });
});

describe("buildWebSocketUrl", () => {
  it("should convert https to wss", () => {
    const wsUrl = buildWebSocketUrl("https://example.com");
    expect(wsUrl).toBe("wss://example.com/socket/websocket");
  });

  it("should convert http to ws", () => {
    const wsUrl = buildWebSocketUrl("http://example.com");
    expect(wsUrl).toBe("ws://example.com/socket/websocket");
  });

  it("should preserve port", () => {
    const wsUrl = buildWebSocketUrl("https://example.com:4000");
    expect(wsUrl).toBe("wss://example.com:4000/socket/websocket");
  });

  it("should handle localhost", () => {
    const wsUrl = buildWebSocketUrl("http://localhost:4000");
    expect(wsUrl).toBe("ws://localhost:4000/socket/websocket");
  });
});
