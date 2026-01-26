import { describe, expect, it } from "vitest";

import {
  AttentionLevel,
  ChannelState,
  ConnectionState,
  createMeasurement,
  defaultBackpressureConfig,
  getRecommendedBatchSize,
  getRecommendedBatchWindow,
  parseBackpressureConfig,
} from "./models.js";

describe("ConnectionState", () => {
  it("should have all expected states", () => {
    expect(ConnectionState.Disconnected).toBe("disconnected");
    expect(ConnectionState.Connecting).toBe("connecting");
    expect(ConnectionState.Connected).toBe("connected");
    expect(ConnectionState.Reconnecting).toBe("reconnecting");
    expect(ConnectionState.Error).toBe("error");
  });
});

describe("AttentionLevel", () => {
  it("should have all expected levels", () => {
    expect(AttentionLevel.None).toBe("none");
    expect(AttentionLevel.Low).toBe("low");
    expect(AttentionLevel.Medium).toBe("medium");
    expect(AttentionLevel.High).toBe("high");
  });
});

describe("ChannelState", () => {
  it("should have all expected states", () => {
    expect(ChannelState.Closed).toBe("closed");
    expect(ChannelState.Joining).toBe("joining");
    expect(ChannelState.Joined).toBe("joined");
    expect(ChannelState.Leaving).toBe("leaving");
    expect(ChannelState.Errored).toBe("errored");
  });
});

describe("getRecommendedBatchWindow", () => {
  it("should return correct windows for each attention level", () => {
    expect(getRecommendedBatchWindow(AttentionLevel.None)).toBe(5000);
    expect(getRecommendedBatchWindow(AttentionLevel.Low)).toBe(2000);
    expect(getRecommendedBatchWindow(AttentionLevel.Medium)).toBe(500);
    expect(getRecommendedBatchWindow(AttentionLevel.High)).toBe(100);
  });
});

describe("getRecommendedBatchSize", () => {
  it("should return correct sizes for each attention level", () => {
    expect(getRecommendedBatchSize(AttentionLevel.None)).toBe(20);
    expect(getRecommendedBatchSize(AttentionLevel.Low)).toBe(10);
    expect(getRecommendedBatchSize(AttentionLevel.Medium)).toBe(5);
    expect(getRecommendedBatchSize(AttentionLevel.High)).toBe(1);
  });
});

describe("createMeasurement", () => {
  it("should create a measurement with provided values", () => {
    const timestamp = Date.now();
    const measurement = createMeasurement("temperature", { value: 23.5 }, timestamp);

    expect(measurement.attributeId).toBe("temperature");
    expect(measurement.payload).toEqual({ value: 23.5 });
    expect(measurement.timestamp).toBe(timestamp);
  });

  it("should auto-generate timestamp if not provided", () => {
    const before = Date.now();
    const measurement = createMeasurement("temperature", { value: 23.5 });
    const after = Date.now();

    expect(measurement.timestamp).toBeGreaterThanOrEqual(before);
    expect(measurement.timestamp).toBeLessThanOrEqual(after);
  });

  it("should handle numeric payloads", () => {
    const measurement = createMeasurement("value", 42);
    expect(measurement.payload).toBe(42);
  });

  it("should handle array payloads", () => {
    const measurement = createMeasurement("position", [1, 2, 3]);
    expect(measurement.payload).toEqual([1, 2, 3]);
  });
});

describe("parseBackpressureConfig", () => {
  it("should parse a valid payload", () => {
    const payload = {
      attention_level: "medium",
      recommended_batch_window: 1000,
      recommended_batch_size: 10,
      timestamp: 123456789,
    };

    const config = parseBackpressureConfig(payload);

    expect(config.attentionLevel).toBe(AttentionLevel.Medium);
    expect(config.recommendedBatchWindow).toBe(1000);
    expect(config.recommendedBatchSize).toBe(10);
    expect(config.timestamp).toBe(123456789);
  });

  it("should use defaults for missing fields", () => {
    const config = parseBackpressureConfig({});

    expect(config.attentionLevel).toBe(AttentionLevel.None);
    expect(config.recommendedBatchWindow).toBe(500);
    expect(config.recommendedBatchSize).toBe(5);
    expect(config.timestamp).toBe(0);
  });

  it("should handle unknown attention levels", () => {
    const config = parseBackpressureConfig({ attention_level: "unknown" });
    expect(config.attentionLevel).toBe(AttentionLevel.None);
  });

  it("should parse all attention levels correctly", () => {
    expect(parseBackpressureConfig({ attention_level: "none" }).attentionLevel).toBe(
      AttentionLevel.None
    );
    expect(parseBackpressureConfig({ attention_level: "low" }).attentionLevel).toBe(
      AttentionLevel.Low
    );
    expect(parseBackpressureConfig({ attention_level: "medium" }).attentionLevel).toBe(
      AttentionLevel.Medium
    );
    expect(parseBackpressureConfig({ attention_level: "high" }).attentionLevel).toBe(
      AttentionLevel.High
    );
  });
});

describe("defaultBackpressureConfig", () => {
  it("should return sensible defaults", () => {
    const config = defaultBackpressureConfig();

    expect(config.attentionLevel).toBe(AttentionLevel.None);
    expect(config.recommendedBatchWindow).toBe(500);
    expect(config.recommendedBatchSize).toBe(5);
    expect(config.timestamp).toBe(0);
  });
});
