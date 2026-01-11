/**
 * Adaptive Quality Manager
 * Monitors RTCRtpSender stats and adjusts video quality based on network conditions
 * Integrates with server-side attention tracking for backpressure control
 */

export class QualityManager {
  constructor(options = {}) {
    // Callbacks
    this.onQualityChange = options.onQualityChange || (() => {});
    this.onStatsUpdate = options.onStatsUpdate || (() => {});

    // RTCPeerConnection reference (set via setConnection)
    this.peerConnection = null;

    // Stats tracking
    this.statsInterval = null;
    this.statsHistory = [];
    this.maxHistorySize = 30; // Keep 30 samples (at 1s interval = 30 seconds)

    // Quality levels and thresholds
    this.qualityLevels = {
      high: { width: 1280, height: 720, frameRate: 30, bitrate: 2500000 },
      medium: { width: 640, height: 480, frameRate: 24, bitrate: 1000000 },
      low: { width: 640, height: 360, frameRate: 15, bitrate: 500000 },
      minimal: { width: 320, height: 240, frameRate: 10, bitrate: 250000 },
    };

    // Current quality state
    this.currentQuality = "high";
    this.targetQuality = "high";

    // Thresholds for quality decisions
    this.thresholds = {
      // Packet loss percentage thresholds
      packetLoss: {
        degradeHigh: 5, // >5% loss = consider downgrade
        degradeMedium: 10, // >10% loss = definite downgrade
        improve: 1, // <1% loss = consider upgrade
      },
      // Round-trip time in ms
      rtt: {
        degradeHigh: 200,
        degradeMedium: 400,
        improve: 100,
      },
      // Jitter in ms
      jitter: {
        degradeHigh: 50,
        degradeMedium: 100,
        improve: 20,
      },
      // Available outbound bandwidth utilization
      bandwidthUtilization: {
        degradeHigh: 0.9, // >90% = congested
        improve: 0.5, // <50% = room to improve
      },
    };

    // Hysteresis - require consistent conditions before changing quality
    this.upgradeCounter = 0;
    this.downgradeCounter = 0;
    this.requiredConsecutiveSamples = 5;

    // Attention-based scaling (from server)
    this.attentionLevel = "normal"; // none, low, normal, high, critical
    this.attentionMultiplier = 1.0;

    // Previous stats for delta calculations
    this.prevStats = null;
  }

  setConnection(peerConnection) {
    this.peerConnection = peerConnection;
  }

  start(intervalMs = 1000) {
    if (this.statsInterval) {
      this.stop();
    }

    this.statsInterval = setInterval(() => {
      this.collectAndAnalyzeStats();
    }, intervalMs);

    console.log("[QualityManager] Started monitoring");
  }

  stop() {
    if (this.statsInterval) {
      clearInterval(this.statsInterval);
      this.statsInterval = null;
    }
    console.log("[QualityManager] Stopped monitoring");
  }

  async collectAndAnalyzeStats() {
    if (!this.peerConnection) return;

    try {
      const stats = await this.peerConnection.getStats();
      const analysis = this.analyzeStats(stats);

      if (analysis) {
        this.statsHistory.push(analysis);
        if (this.statsHistory.length > this.maxHistorySize) {
          this.statsHistory.shift();
        }

        this.onStatsUpdate(analysis);
        this.evaluateQuality(analysis);
      }
    } catch (error) {
      console.error("[QualityManager] Error collecting stats:", error);
    }
  }

  analyzeStats(stats) {
    const result = {
      timestamp: Date.now(),
      outbound: { video: null, audio: null },
      inbound: { video: null, audio: null },
      connection: null,
    };

    stats.forEach((report) => {
      if (report.type === "outbound-rtp" && report.kind === "video") {
        result.outbound.video = this.extractOutboundVideoStats(report, stats);
      } else if (report.type === "outbound-rtp" && report.kind === "audio") {
        result.outbound.audio = this.extractOutboundAudioStats(report);
      } else if (report.type === "inbound-rtp" && report.kind === "video") {
        result.inbound.video = this.extractInboundVideoStats(report);
      } else if (report.type === "inbound-rtp" && report.kind === "audio") {
        result.inbound.audio = this.extractInboundAudioStats(report);
      } else if (report.type === "candidate-pair" && report.state === "succeeded") {
        result.connection = this.extractConnectionStats(report);
      }
    });

    // Calculate deltas if we have previous stats
    if (this.prevStats && result.outbound.video) {
      result.outbound.video.packetLossRate = this.calculatePacketLossRate(
        result.outbound.video,
        this.prevStats.outbound?.video
      );
    }

    this.prevStats = result;
    return result;
  }

  extractOutboundVideoStats(report, allStats) {
    const result = {
      bytesSent: report.bytesSent || 0,
      packetsSent: report.packetsSent || 0,
      framesEncoded: report.framesEncoded || 0,
      framesPerSecond: report.framesPerSecond || 0,
      frameWidth: report.frameWidth || 0,
      frameHeight: report.frameHeight || 0,
      qualityLimitationReason: report.qualityLimitationReason || "none",
      qualityLimitationDurations: report.qualityLimitationDurations || {},
      retransmittedPacketsSent: report.retransmittedPacketsSent || 0,
      nackCount: report.nackCount || 0,
      firCount: report.firCount || 0,
      pliCount: report.pliCount || 0,
      targetBitrate: null,
      encoderImplementation: report.encoderImplementation || "unknown",
    };

    // Get target bitrate from remote-inbound-rtp if available
    if (report.remoteId) {
      const remoteReport = allStats.get(report.remoteId);
      if (remoteReport) {
        result.roundTripTime = remoteReport.roundTripTime
          ? remoteReport.roundTripTime * 1000
          : null;
        result.packetsLost = remoteReport.packetsLost || 0;
        result.jitter = remoteReport.jitter ? remoteReport.jitter * 1000 : null;
      }
    }

    return result;
  }

  extractOutboundAudioStats(report) {
    return {
      bytesSent: report.bytesSent || 0,
      packetsSent: report.packetsSent || 0,
    };
  }

  extractInboundVideoStats(report) {
    return {
      bytesReceived: report.bytesReceived || 0,
      packetsReceived: report.packetsReceived || 0,
      packetsLost: report.packetsLost || 0,
      framesDecoded: report.framesDecoded || 0,
      framesDropped: report.framesDropped || 0,
      framesPerSecond: report.framesPerSecond || 0,
      jitter: report.jitter ? report.jitter * 1000 : null,
      frameWidth: report.frameWidth || 0,
      frameHeight: report.frameHeight || 0,
    };
  }

  extractInboundAudioStats(report) {
    return {
      bytesReceived: report.bytesReceived || 0,
      packetsReceived: report.packetsReceived || 0,
      packetsLost: report.packetsLost || 0,
      jitter: report.jitter ? report.jitter * 1000 : null,
    };
  }

  extractConnectionStats(report) {
    return {
      currentRoundTripTime: report.currentRoundTripTime
        ? report.currentRoundTripTime * 1000
        : null,
      availableOutgoingBitrate: report.availableOutgoingBitrate || null,
      bytesReceived: report.bytesReceived || 0,
      bytesSent: report.bytesSent || 0,
      requestsReceived: report.requestsReceived || 0,
      requestsSent: report.requestsSent || 0,
      responsesReceived: report.responsesReceived || 0,
      responsesSent: report.responsesSent || 0,
    };
  }

  calculatePacketLossRate(current, previous) {
    if (!previous || !current) return 0;

    const packetsSentDelta = current.packetsSent - previous.packetsSent;
    const packetsLostDelta = (current.packetsLost || 0) - (previous.packetsLost || 0);

    if (packetsSentDelta <= 0) return 0;
    return Math.max(0, (packetsLostDelta / packetsSentDelta) * 100);
  }

  evaluateQuality(stats) {
    const decision = this.makeQualityDecision(stats);

    if (decision === "upgrade") {
      this.downgradeCounter = 0;
      this.upgradeCounter++;

      if (this.upgradeCounter >= this.requiredConsecutiveSamples) {
        this.upgradeQuality();
        this.upgradeCounter = 0;
      }
    } else if (decision === "downgrade") {
      this.upgradeCounter = 0;
      this.downgradeCounter++;

      if (this.downgradeCounter >= this.requiredConsecutiveSamples) {
        this.downgradeQuality();
        this.downgradeCounter = 0;
      }
    } else {
      // Maintain - slowly decay counters
      this.upgradeCounter = Math.max(0, this.upgradeCounter - 1);
      this.downgradeCounter = Math.max(0, this.downgradeCounter - 1);
    }
  }

  makeQualityDecision(stats) {
    const video = stats.outbound?.video;
    const connection = stats.connection;

    if (!video) return "maintain";

    // Check for quality limitation by encoder (CPU/bandwidth constraint)
    if (
      video.qualityLimitationReason === "bandwidth" ||
      video.qualityLimitationReason === "cpu"
    ) {
      return "downgrade";
    }

    // Check packet loss
    if (video.packetLossRate > this.thresholds.packetLoss.degradeMedium) {
      return "downgrade";
    }

    // Check RTT
    const rtt = video.roundTripTime || connection?.currentRoundTripTime;
    if (rtt && rtt > this.thresholds.rtt.degradeMedium) {
      return "downgrade";
    }

    // Check jitter
    if (video.jitter && video.jitter > this.thresholds.jitter.degradeMedium) {
      return "downgrade";
    }

    // Check for NACK/PLI storms (receiver requesting retransmits)
    if (this.prevStats?.outbound?.video) {
      const nackDelta = video.nackCount - (this.prevStats.outbound.video.nackCount || 0);
      const pliDelta = video.pliCount - (this.prevStats.outbound.video.pliCount || 0);
      if (nackDelta > 10 || pliDelta > 2) {
        return "downgrade";
      }
    }

    // Consider attention-based backpressure
    if (this.attentionLevel === "critical") {
      return "downgrade";
    }

    // Check if conditions are good enough to upgrade
    const canUpgrade =
      video.packetLossRate < this.thresholds.packetLoss.improve &&
      (!rtt || rtt < this.thresholds.rtt.improve) &&
      (!video.jitter || video.jitter < this.thresholds.jitter.improve) &&
      video.qualityLimitationReason === "none" &&
      this.attentionLevel !== "high" &&
      this.attentionLevel !== "critical";

    if (canUpgrade && this.currentQuality !== "high") {
      return "upgrade";
    }

    return "maintain";
  }

  upgradeQuality() {
    const levels = ["minimal", "low", "medium", "high"];
    const currentIndex = levels.indexOf(this.currentQuality);

    if (currentIndex < levels.length - 1) {
      const newQuality = levels[currentIndex + 1];
      console.log(`[QualityManager] Upgrading quality: ${this.currentQuality} -> ${newQuality}`);
      this.setQuality(newQuality);
    }
  }

  downgradeQuality() {
    const levels = ["minimal", "low", "medium", "high"];
    const currentIndex = levels.indexOf(this.currentQuality);

    if (currentIndex > 0) {
      const newQuality = levels[currentIndex - 1];
      console.log(`[QualityManager] Downgrading quality: ${this.currentQuality} -> ${newQuality}`);
      this.setQuality(newQuality);
    }
  }

  setQuality(level) {
    if (!this.qualityLevels[level]) {
      console.warn(`[QualityManager] Unknown quality level: ${level}`);
      return;
    }

    this.currentQuality = level;
    this.onQualityChange(level, this.qualityLevels[level]);
  }

  // Called by server/attention tracker to influence quality decisions
  setAttentionLevel(level) {
    const validLevels = ["none", "low", "normal", "high", "critical"];
    if (!validLevels.includes(level)) {
      console.warn(`[QualityManager] Unknown attention level: ${level}`);
      return;
    }

    this.attentionLevel = level;

    // Map attention to multiplier for immediate effect if critical
    switch (level) {
      case "critical":
        this.attentionMultiplier = 0.25;
        // Force immediate downgrade to minimal
        if (this.currentQuality !== "minimal") {
          this.setQuality("minimal");
        }
        break;
      case "high":
        this.attentionMultiplier = 0.5;
        if (this.currentQuality === "high") {
          this.setQuality("medium");
        }
        break;
      case "normal":
        this.attentionMultiplier = 1.0;
        break;
      case "low":
      case "none":
        this.attentionMultiplier = 1.0;
        break;
    }
  }

  // Apply quality settings to RTCRtpSender
  async applyToSender(sender) {
    if (!sender || sender.track?.kind !== "video") return;

    const params = sender.getParameters();
    if (!params.encodings || params.encodings.length === 0) {
      params.encodings = [{}];
    }

    const quality = this.qualityLevels[this.currentQuality];

    params.encodings[0].maxBitrate = Math.floor(
      quality.bitrate * this.attentionMultiplier
    );
    params.encodings[0].maxFramerate = Math.floor(
      quality.frameRate * this.attentionMultiplier
    );

    try {
      await sender.setParameters(params);
      console.log(
        `[QualityManager] Applied to sender: ${quality.frameRate * this.attentionMultiplier}fps, ${quality.bitrate * this.attentionMultiplier}bps`
      );
    } catch (error) {
      console.error("[QualityManager] Failed to apply sender parameters:", error);
    }
  }

  // Get current stats summary for UI
  getStatsSummary() {
    if (this.statsHistory.length === 0) return null;

    const recent = this.statsHistory.slice(-5);
    const avgPacketLoss =
      recent.reduce((sum, s) => sum + (s.outbound?.video?.packetLossRate || 0), 0) /
      recent.length;
    const avgRtt =
      recent.reduce(
        (sum, s) =>
          sum +
          (s.outbound?.video?.roundTripTime ||
            s.connection?.currentRoundTripTime ||
            0),
        0
      ) / recent.length;
    const currentFps = this.statsHistory[this.statsHistory.length - 1]?.outbound?.video
      ?.framesPerSecond;

    return {
      quality: this.currentQuality,
      attentionLevel: this.attentionLevel,
      avgPacketLoss: avgPacketLoss.toFixed(2),
      avgRtt: avgRtt.toFixed(0),
      currentFps: currentFps?.toFixed(1) || "N/A",
      targetSettings: this.qualityLevels[this.currentQuality],
    };
  }

  destroy() {
    this.stop();
    this.statsHistory = [];
    this.prevStats = null;
    this.peerConnection = null;
  }
}
