/**
 * Call session implementation for video/voice communication.
 * @module call
 */

import { PhoenixChannel } from "./channel.js";
import { SensoctoError } from "./errors.js";
import { type AnyCallEvent, type CallParticipant, type IceServer } from "./models.js";

/**
 * Callback for call events.
 */
export type CallEventHandler = (event: AnyCallEvent) => void;

/**
 * Session for video/voice communication.
 *
 * Manages WebRTC signaling through Phoenix channels for
 * real-time video and voice calls.
 *
 * @example
 * ```typescript
 * const session = await client.joinCall("room-123", "user-456");
 *
 * session.onEvent((event) => {
 *   switch (event.type) {
 *     case "participant_joined":
 *       console.log("Joined:", event.participant);
 *       break;
 *     case "media_event":
 *       // Handle WebRTC signaling
 *       handleMediaEvent(event.data);
 *       break;
 *   }
 * });
 *
 * // Join the actual call
 * await session.joinCall();
 *
 * // Send WebRTC signaling data
 * await session.sendMediaEvent(sdpOffer);
 * ```
 */
export class CallSession {
  private readonly channel: PhoenixChannel;
  private readonly _roomId: string;
  private readonly _userId: string;
  private _iceServers: IceServer[];
  private _inCall = false;
  private _endpointId: string | null = null;
  private eventHandlers: CallEventHandler[] = [];

  /**
   * Creates a new call session.
   *
   * @param channel - The Phoenix channel for this call
   * @param roomId - The room ID
   * @param userId - The user ID
   * @param iceServers - ICE servers for WebRTC
   */
  constructor(
    channel: PhoenixChannel,
    roomId: string,
    userId: string,
    iceServers: IceServer[] = []
  ) {
    this.channel = channel;
    this._roomId = roomId;
    this._userId = userId;
    this._iceServers = iceServers;

    this.setupEventHandlers();
  }

  /**
   * Returns the room ID.
   */
  get roomId(): string {
    return this._roomId;
  }

  /**
   * Returns the user ID.
   */
  get userId(): string {
    return this._userId;
  }

  /**
   * Returns whether the user is in the call.
   */
  get inCall(): boolean {
    return this._inCall;
  }

  /**
   * Returns the endpoint ID.
   */
  get endpointId(): string | null {
    return this._endpointId;
  }

  /**
   * Returns the ICE servers.
   */
  get iceServers(): IceServer[] {
    return this._iceServers;
  }

  /**
   * Returns the ICE servers in RTCPeerConnection format.
   */
  get rtcIceServers(): RTCIceServer[] {
    return this._iceServers.map((server) => {
      const result: RTCIceServer = { urls: server.urls };
      if (server.username !== undefined) {
        result.username = server.username;
      }
      if (server.credential !== undefined) {
        result.credential = server.credential;
      }
      return result;
    });
  }

  /**
   * Registers an event handler.
   *
   * @param handler - Callback function called when events are received
   * @returns A function to unsubscribe the handler
   */
  onEvent(handler: CallEventHandler): () => void {
    this.eventHandlers.push(handler);

    return () => {
      const index = this.eventHandlers.indexOf(handler);
      if (index !== -1) {
        this.eventHandlers.splice(index, 1);
      }
    };
  }

  /**
   * Joins the actual call.
   *
   * @returns The join response with endpoint_id and participants
   * @throws {SensoctoError} If not connected to channel
   */
  async joinCall(): Promise<{
    endpointId: string;
    participants: Record<string, CallParticipant>;
  }> {
    if (!this.channel.isJoined) {
      throw new SensoctoError("Channel not joined");
    }

    const reply = await this.channel.push("join_call", {});

    if (reply.status === "ok") {
      this._inCall = true;
      this._endpointId = (reply.response["endpoint_id"] as string) ?? null;

      const rawParticipants = (reply.response["participants"] as Record<string, unknown>) ?? {};
      const participants: Record<string, CallParticipant> = {};

      for (const [odUserId, data] of Object.entries(rawParticipants)) {
        const p = data as Record<string, unknown>;
        const participant: CallParticipant = {
          userId: (p["user_id"] as string) ?? odUserId,
          endpointId: (p["endpoint_id"] as string) ?? "",
          userInfo: (p["user_info"] as Record<string, unknown>) ?? {},
          audioEnabled: (p["audio_enabled"] as boolean) ?? false,
          videoEnabled: (p["video_enabled"] as boolean) ?? false,
        };
        if (typeof p["joined_at"] === "string") {
          participant.joinedAt = p["joined_at"];
        }
        participants[odUserId] = participant;
      }

      return { endpointId: this._endpointId ?? "", participants };
    }

    throw new SensoctoError(`Failed to join call: ${JSON.stringify(reply.response)}`);
  }

  /**
   * Leaves the call.
   */
  async leaveCall(): Promise<void> {
    if (!this._inCall) {
      return;
    }

    await this.channel.push("leave_call", {});
    this._inCall = false;
    this._endpointId = null;
  }

  /**
   * Sends a media event (SDP offer/answer, ICE candidate).
   *
   * @param data - The media event data
   * @throws {SensoctoError} If not in call
   */
  async sendMediaEvent(data: unknown): Promise<void> {
    if (!this._inCall) {
      throw new SensoctoError("Not in call");
    }

    await this.channel.pushNoReply("media_event", { data });
  }

  /**
   * Toggles the local audio state.
   *
   * @param enabled - Whether audio should be enabled
   * @throws {SensoctoError} If not in call
   */
  async toggleAudio(enabled: boolean): Promise<void> {
    if (!this._inCall) {
      throw new SensoctoError("Not in call");
    }

    await this.channel.push("toggle_audio", { enabled });
  }

  /**
   * Toggles the local video state.
   *
   * @param enabled - Whether video should be enabled
   * @throws {SensoctoError} If not in call
   */
  async toggleVideo(enabled: boolean): Promise<void> {
    if (!this._inCall) {
      throw new SensoctoError("Not in call");
    }

    await this.channel.push("toggle_video", { enabled });
  }

  /**
   * Sets the video quality.
   *
   * @param quality - Quality level ("high", "medium", "low", or "auto")
   * @throws {SensoctoError} If not in call
   */
  async setQuality(quality: "high" | "medium" | "low" | "auto"): Promise<void> {
    if (!this._inCall) {
      throw new SensoctoError("Not in call");
    }

    await this.channel.push("set_quality", { quality });
  }

  /**
   * Gets the current participants.
   *
   * @returns Dictionary mapping user_id to CallParticipant
   */
  async getParticipants(): Promise<Record<string, CallParticipant>> {
    const reply = await this.channel.push("get_participants", {});

    if (reply.status === "ok") {
      const rawParticipants = (reply.response["participants"] as Record<string, unknown>) ?? {};
      const participants: Record<string, CallParticipant> = {};

      for (const [odUserId, data] of Object.entries(rawParticipants)) {
        const p = data as Record<string, unknown>;
        const participant: CallParticipant = {
          userId: (p["user_id"] as string) ?? odUserId,
          endpointId: (p["endpoint_id"] as string) ?? "",
          userInfo: (p["user_info"] as Record<string, unknown>) ?? {},
          audioEnabled: (p["audio_enabled"] as boolean) ?? false,
          videoEnabled: (p["video_enabled"] as boolean) ?? false,
        };
        if (typeof p["joined_at"] === "string") {
          participant.joinedAt = p["joined_at"];
        }
        participants[odUserId] = participant;
      }

      return participants;
    }

    return {};
  }

  /**
   * Closes the call session.
   */
  async close(): Promise<void> {
    if (this._inCall) {
      await this.leaveCall();
    }

    await this.channel.leave();
    this.eventHandlers = [];
  }

  private setupEventHandlers(): void {
    this.channel.on("participant_joined", (payload) => {
      const participant: CallParticipant = {
        userId: (payload["user_id"] as string) ?? "",
        endpointId: (payload["endpoint_id"] as string) ?? "",
        userInfo: (payload["user_info"] as Record<string, unknown>) ?? {},
        audioEnabled: (payload["audio_enabled"] as boolean) ?? false,
        videoEnabled: (payload["video_enabled"] as boolean) ?? false,
      };
      if (typeof payload["joined_at"] === "string") {
        participant.joinedAt = payload["joined_at"];
      }
      this.dispatchEvent({
        type: "participant_joined",
        participant,
      });
    });

    this.channel.on("participant_left", (payload) => {
      this.dispatchEvent({
        type: "participant_left",
        userId: (payload["user_id"] as string) ?? "",
        crashed: (payload["crashed"] as boolean) ?? false,
      });
    });

    this.channel.on("media_event", (payload) => {
      this.dispatchEvent({
        type: "media_event",
        data: payload["data"],
      });
    });

    this.channel.on("participant_audio_changed", (payload) => {
      this.dispatchEvent({
        type: "participant_audio_changed",
        userId: (payload["user_id"] as string) ?? "",
        enabled: (payload["audio_enabled"] as boolean) ?? false,
      });
    });

    this.channel.on("participant_video_changed", (payload) => {
      this.dispatchEvent({
        type: "participant_video_changed",
        userId: (payload["user_id"] as string) ?? "",
        enabled: (payload["video_enabled"] as boolean) ?? false,
      });
    });

    this.channel.on("quality_changed", (payload) => {
      this.dispatchEvent({
        type: "quality_changed",
        quality: (payload["quality"] as string) ?? "",
      });
    });

    this.channel.on("call_ended", () => {
      this._inCall = false;
      this.dispatchEvent({ type: "call_ended" });
    });
  }

  private dispatchEvent(event: AnyCallEvent): void {
    for (const handler of this.eventHandlers) {
      try {
        handler(event);
      } catch (error) {
        console.error("Error in call event handler:", error);
      }
    }
  }
}
