import { describe, expect, it } from "vitest";

import {
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

describe("SensoctoError", () => {
  it("should create error with message", () => {
    const error = new SensoctoError("Test error");
    expect(error.message).toBe("Test error");
    expect(error.name).toBe("SensoctoError");
    expect(error.cause).toBeUndefined();
  });

  it("should create error with cause", () => {
    const cause = new Error("Original error");
    const error = new SensoctoError("Test error", cause);
    expect(error.cause).toBe(cause);
  });

  it("should format toString with cause", () => {
    const cause = new Error("Original error");
    const error = new SensoctoError("Test error", cause);
    expect(error.toString()).toBe("Test error: Original error");
  });

  it("should format toString without cause", () => {
    const error = new SensoctoError("Test error");
    expect(error.toString()).toBe("Test error");
  });

  it("should be instanceof Error", () => {
    const error = new SensoctoError("Test");
    expect(error).toBeInstanceOf(Error);
    expect(error).toBeInstanceOf(SensoctoError);
  });
});

describe("ConnectionError", () => {
  it("should create error with message", () => {
    const error = new ConnectionError("Connection failed");
    expect(error.message).toBe("Connection failed");
    expect(error.name).toBe("ConnectionError");
  });

  it("should be instanceof SensoctoError", () => {
    const error = new ConnectionError("Test");
    expect(error).toBeInstanceOf(SensoctoError);
  });
});

describe("ChannelJoinError", () => {
  it("should create error with topic and reason", () => {
    const error = new ChannelJoinError("room:lobby", "unauthorized");
    expect(error.message).toBe("Failed to join channel 'room:lobby': unauthorized");
    expect(error.name).toBe("ChannelJoinError");
    expect(error.topic).toBe("room:lobby");
    expect(error.reason).toBe("unauthorized");
  });
});

describe("AuthenticationError", () => {
  it("should create error with default message", () => {
    const error = new AuthenticationError();
    expect(error.message).toBe("Authentication failed");
    expect(error.name).toBe("AuthenticationError");
  });

  it("should create error with custom message", () => {
    const error = new AuthenticationError("Invalid token");
    expect(error.message).toBe("Invalid token");
  });
});

describe("TimeoutError", () => {
  it("should create error with timeout duration", () => {
    const error = new TimeoutError(5000);
    expect(error.message).toBe("Operation timed out after 5000ms");
    expect(error.name).toBe("TimeoutError");
    expect(error.timeoutMs).toBe(5000);
  });
});

describe("InvalidConfigError", () => {
  it("should create error with message", () => {
    const error = new InvalidConfigError("Server URL is required");
    expect(error.message).toBe("Server URL is required");
    expect(error.name).toBe("InvalidConfigError");
  });
});

describe("DisconnectedError", () => {
  it("should create error with default message", () => {
    const error = new DisconnectedError();
    expect(error.message).toBe("Client is disconnected");
    expect(error.name).toBe("DisconnectedError");
  });
});

describe("InvalidAttributeIdError", () => {
  it("should create error with attribute ID and reason", () => {
    const error = new InvalidAttributeIdError("123invalid", "must start with letter");
    expect(error.message).toBe("Invalid attribute ID '123invalid': must start with letter");
    expect(error.name).toBe("InvalidAttributeIdError");
    expect(error.attributeId).toBe("123invalid");
    expect(error.reason).toBe("must start with letter");
  });
});

describe("ChannelError", () => {
  it("should create error with topic and message", () => {
    const error = new ChannelError("room:lobby", "Channel is not joined");
    expect(error.message).toBe("Channel is not joined");
    expect(error.name).toBe("ChannelError");
    expect(error.topic).toBe("room:lobby");
  });
});
