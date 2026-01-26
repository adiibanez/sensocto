/**
 * Error types for the Sensocto client.
 * @module errors
 */

/**
 * Base error class for all Sensocto errors.
 */
export class SensoctoError extends Error {
  /** The underlying cause of this error, if any. */
  public override readonly cause?: Error | undefined;

  constructor(message: string, cause?: Error) {
    super(message);
    this.name = "SensoctoError";
    this.cause = cause;

    // Maintains proper stack trace for where our error was thrown (only in V8)
    if (Error.captureStackTrace) {
      Error.captureStackTrace(this, this.constructor);
    }
  }

  override toString(): string {
    if (this.cause) {
      return `${this.message}: ${this.cause.message}`;
    }
    return this.message;
  }
}

/**
 * Raised when connection to the server fails.
 */
export class ConnectionError extends SensoctoError {
  constructor(message: string, cause?: Error) {
    super(message, cause);
    this.name = "ConnectionError";
  }
}

/**
 * Raised when joining a channel fails.
 */
export class ChannelJoinError extends SensoctoError {
  /** The topic that failed to join. */
  public readonly topic: string;
  /** The reason for the failure. */
  public readonly reason: string;

  constructor(topic: string, reason: string) {
    super(`Failed to join channel '${topic}': ${reason}`);
    this.name = "ChannelJoinError";
    this.topic = topic;
    this.reason = reason;
  }
}

/**
 * Raised when authentication fails.
 */
export class AuthenticationError extends SensoctoError {
  constructor(message: string = "Authentication failed") {
    super(message);
    this.name = "AuthenticationError";
  }
}

/**
 * Raised when an operation times out.
 */
export class TimeoutError extends SensoctoError {
  /** The timeout duration in milliseconds. */
  public readonly timeoutMs: number;

  constructor(timeoutMs: number) {
    super(`Operation timed out after ${timeoutMs}ms`);
    this.name = "TimeoutError";
    this.timeoutMs = timeoutMs;
  }
}

/**
 * Raised when configuration is invalid.
 */
export class InvalidConfigError extends SensoctoError {
  constructor(message: string) {
    super(message);
    this.name = "InvalidConfigError";
  }
}

/**
 * Raised when trying to perform an operation while disconnected.
 */
export class DisconnectedError extends SensoctoError {
  constructor() {
    super("Client is disconnected");
    this.name = "DisconnectedError";
  }
}

/**
 * Raised when an attribute ID is invalid.
 */
export class InvalidAttributeIdError extends SensoctoError {
  /** The invalid attribute ID. */
  public readonly attributeId: string;
  /** The reason it is invalid. */
  public readonly reason: string;

  constructor(attributeId: string, reason: string) {
    super(`Invalid attribute ID '${attributeId}': ${reason}`);
    this.name = "InvalidAttributeIdError";
    this.attributeId = attributeId;
    this.reason = reason;
  }
}

/**
 * Raised when a channel operation fails.
 */
export class ChannelError extends SensoctoError {
  /** The topic of the channel. */
  public readonly topic: string;

  constructor(topic: string, message: string, cause?: Error) {
    super(message, cause);
    this.name = "ChannelError";
    this.topic = topic;
  }
}
