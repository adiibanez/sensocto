// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import topbar from "../vendor/topbar"
import logger from "./logger.js"
// Import hooks including MediaPlayerHook for YouTube playback
import BaseHooks from "./hooks"
// Import directly from hooks.svelte module to avoid svelte/server dependency (from render.js)
import { getHooks } from "../../deps/live_svelte/assets/js/live_svelte/hooks.svelte"
import * as Components from "../svelte/**/*.svelte"
//import * as Components from "../svelte/SenseApp.svelte"

import {
  openDatabase,
  handleClearData,
  handleAppendData,
  handleAppendAndReadData,
  handleSeedData,
  handleGetLastTimestamp,
  handleGetAllLatestTimestamps,
  setDebug
} from './indexeddb.js';

// Connection monitor for offline resilience
import connectionMonitor from './connection-monitor.js';

// Delta encoding decoder for high-frequency ECG data
import { decodeECG, isDeltaEncoded } from './encoding/delta_decoder.js';

// Room-related hooks
import { RoomStorage, CopyToClipboard, QRCode } from './hooks/room_storage.js';

// Attention tracking hooks for back-pressure control
import { AttentionTracker, SensorPinControl } from './hooks/attention_tracker.js';

// Video/Voice call hooks
import { CallHook, VideoTileHook, CallControlsHook } from './webrtc/call_hooks.js';

// Mini call indicator for persistent call UI
import { MiniCallIndicatorHook } from './hooks/mini_call_indicator.js';

// User video tile for attention-based video in Users tab
import { UserVideoTileHook } from './hooks/user_video_tile.js';

// MIDI output for biometric → MIDI CC mapping
import MidiOutputHook from './hooks/midi_output_hook.js';

// Avatar ecosystem - bioluminescent Gaussian splat scene driven by sensor data
import AvatarSplatHook from './hooks/avatar_splat_hook.js';

// Sensor background visualization for sign-in page
import { SensorBackgroundHook } from './hooks/sensor_background_hook.js';

// Safari has limited support for module workers - wrap in try/catch to prevent app crash
try {
  window.workerStorage = new Worker('/assets/worker-storage.js?' + Math.random(), { type: 'module' });
} catch (e) {
  console.warn('Module worker not supported, falling back to inline worker simulation');
  // Create a mock worker for Safari that does nothing but doesn't break the app
  window.workerStorage = {
    postMessage: () => {},
    addEventListener: () => {},
    removeEventListener: () => {},
    terminate: () => {}
  };
}
let Hooks = {}

// Register room hooks
Hooks.RoomStorage = RoomStorage;
Hooks.CopyToClipboard = CopyToClipboard;
Hooks.QRCode = QRCode;

// Register attention tracking hooks
Hooks.AttentionTracker = AttentionTracker;
Hooks.SensorPinControl = SensorPinControl;

// Register video/voice call hooks
Hooks.CallHook = CallHook;
Hooks.VideoTileHook = VideoTileHook;
Hooks.CallControlsHook = CallControlsHook;
Hooks.MiniCallIndicator = MiniCallIndicatorHook;
Hooks.UserVideoTile = UserVideoTileHook;

// MIDI output hook
Hooks.MidiOutputHook = MidiOutputHook;

// Avatar ecosystem hook
Hooks.AvatarSplatHook = AvatarSplatHook;

// Sensor background hook for sign-in page
Hooks.SensorBackgroundHook = SensorBackgroundHook;

// Vibrate hook - vibrates device and plays sound on every button press
// Supports repetitive clicks on same button (uses timestamp to detect)
// Sound plays by default (set data-play-sound="false" to disable)
// NOTE: Does NOT trigger on mount - only on actual button press updates
Hooks.Vibrate = {
  mounted() {
    this.lastValue = this.el.dataset.value;
    this.lastTimestamp = this.el.dataset.timestamp || '0';
    this.lastEvent = this.el.dataset.event;
    this.audioContext = null;
    // Don't trigger notification on mount - only on actual updates
    // This prevents sound/vibration when joining/leaving pages
  },

  updated() {
    const newValue = this.el.dataset.value;
    const newTimestamp = this.el.dataset.timestamp || Date.now().toString();
    const newEvent = this.el.dataset.event;

    // Trigger if value changed OR if timestamp changed (for repetitive clicks)
    const valueChanged = newValue !== this.lastValue;
    const timestampChanged = newTimestamp !== this.lastTimestamp;

    if (valueChanged || timestampChanged) {
      this.lastValue = newValue;
      this.lastTimestamp = newTimestamp;
      this.lastEvent = newEvent;

      if (newValue && newValue !== 'null' && newValue !== 'undefined') {
        // Only vibrate on press events (not release)
        if (!newEvent || newEvent === 'press') {
          this.triggerNotification(newValue);
        }
      }
    }
  },

  triggerNotification(value) {
    const buttonNumber = parseInt(value, 10) || 1;
    const vibrateDuration = buttonNumber * 100;

    // Vibrate on mobile devices
    if (navigator.vibrate) {
      const result = navigator.vibrate(vibrateDuration);
      console.log(`[Vibrate] button=${buttonNumber}, duration=${vibrateDuration}ms, success=${result}`);
    } else {
      console.log('[Vibrate] navigator.vibrate not available');
    }

    // Play sound unless explicitly disabled
    if (this.el.dataset.playSound !== 'false') {
      this.playBeep(buttonNumber);
    }
  },

  playBeep(buttonNumber = 1) {
    try {
      if (!this.audioContext) {
        this.audioContext = new (window.AudioContext || window.webkitAudioContext)();
      }

      const ctx = this.audioContext;
      const now = ctx.currentTime;

      // Pleasant "blob" frequencies - pentatonic scale for musical harmony
      const blobFrequencies = {
        1: 261.6,  // C4
        2: 293.7,  // D4
        3: 329.6,  // E4
        4: 392.0,  // G4
        5: 440.0,  // A4
        6: 523.3,  // C5
        7: 587.3,  // D5
        8: 659.3   // E5
      };
      const baseFreq = blobFrequencies[buttonNumber] || 392.0;

      // Create main oscillator with slight detune for warmth
      const osc1 = ctx.createOscillator();
      const osc2 = ctx.createOscillator();
      const gainNode = ctx.createGain();
      const filterNode = ctx.createBiquadFilter();

      // Route through low-pass filter for softer sound
      osc1.connect(filterNode);
      osc2.connect(filterNode);
      filterNode.connect(gainNode);
      gainNode.connect(ctx.destination);

      // Oscillator setup - triangle waves are softer than sine
      osc1.type = 'triangle';
      osc2.type = 'sine';
      osc1.frequency.setValueAtTime(baseFreq, now);
      osc2.frequency.setValueAtTime(baseFreq * 2, now); // Octave harmonic

      // Frequency "plop" - start higher and drop quickly for blob effect
      osc1.frequency.setValueAtTime(baseFreq * 1.5, now);
      osc1.frequency.exponentialRampToValueAtTime(baseFreq * 0.8, now + 0.08);
      osc2.frequency.setValueAtTime(baseFreq * 3, now);
      osc2.frequency.exponentialRampToValueAtTime(baseFreq * 1.6, now + 0.06);

      // Low-pass filter for rounded, bubbly tone
      filterNode.type = 'lowpass';
      filterNode.frequency.setValueAtTime(2000, now);
      filterNode.frequency.exponentialRampToValueAtTime(400, now + 0.15);
      filterNode.Q.value = 2;

      // Volume envelope - quick attack, smooth decay
      gainNode.gain.setValueAtTime(0, now);
      gainNode.gain.linearRampToValueAtTime(0.25, now + 0.01); // Quick attack
      gainNode.gain.exponentialRampToValueAtTime(0.08, now + 0.1);
      gainNode.gain.exponentialRampToValueAtTime(0.001, now + 0.25);

      // Start and stop
      osc1.start(now);
      osc2.start(now);
      osc1.stop(now + 0.3);
      osc2.stop(now + 0.3);
    } catch (e) {
      console.warn('[Vibrate] Could not play blob sound:', e);
    }
  }
};

// NotificationSound hook - plays an attention sound when the element appears (mounted)
// Used for control request modals to alert the user
// Optionally vibrates on mobile devices
Hooks.NotificationSound = {
  mounted() {
    this.playNotificationSound();

    // Also vibrate on mobile
    if (navigator.vibrate) {
      navigator.vibrate([100, 50, 100, 50, 200]); // Pattern: short-pause-short-pause-long
    }
  },

  playNotificationSound() {
    try {
      const ctx = new (window.AudioContext || window.webkitAudioContext)();
      const now = ctx.currentTime;

      // Play a two-tone attention chime (like a doorbell)
      // First tone - higher
      const osc1 = ctx.createOscillator();
      const gain1 = ctx.createGain();
      osc1.connect(gain1);
      gain1.connect(ctx.destination);
      osc1.type = 'sine';
      osc1.frequency.setValueAtTime(880, now); // A5
      gain1.gain.setValueAtTime(0, now);
      gain1.gain.linearRampToValueAtTime(0.3, now + 0.02);
      gain1.gain.exponentialRampToValueAtTime(0.01, now + 0.3);
      osc1.start(now);
      osc1.stop(now + 0.35);

      // Second tone - lower (classic ding-dong pattern)
      const osc2 = ctx.createOscillator();
      const gain2 = ctx.createGain();
      osc2.connect(gain2);
      gain2.connect(ctx.destination);
      osc2.type = 'sine';
      osc2.frequency.setValueAtTime(659.25, now + 0.15); // E5
      gain2.gain.setValueAtTime(0, now);
      gain2.gain.setValueAtTime(0, now + 0.15);
      gain2.gain.linearRampToValueAtTime(0.3, now + 0.17);
      gain2.gain.exponentialRampToValueAtTime(0.01, now + 0.5);
      osc2.start(now + 0.15);
      osc2.stop(now + 0.55);

      console.log('[NotificationSound] Played attention chime');
    } catch (e) {
      console.warn('[NotificationSound] Could not play sound:', e);
    }
  }
};

// CountdownTimer hook - displays a countdown from data-seconds
// Used for control request modals to show time remaining before auto-transfer
// NOTE: hooks.js has a more robust version that overrides this one at runtime
Hooks.CountdownTimer = {
  mounted() {
    const seconds = parseInt(this.el.dataset.seconds) || 30;
    this.remaining = seconds;
    this.display = this.el.querySelector('.countdown-display');

    this.interval = setInterval(() => {
      this.remaining--;
      if (this.display) {
        this.display.textContent = this.remaining;
      }
      this.el.setAttribute('aria-label', `${this.remaining} seconds remaining`);
      if (this.remaining <= 0) {
        clearInterval(this.interval);
      }
    }, 1000);
  },

  destroyed() {
    if (this.interval) {
      clearInterval(this.interval);
    }
  }
};

Hooks.Formless = {
  mounted() {

    console.log('Formless mount', this.el.dataset.sensor_id, this.el.dataset.attribute_id);

    this.el.addEventListener('change', event => {

      console.log('Formless change', this.el.dataset.event, this.el.dataset.sensor_id, this.el.dataset.attribute_id, this.el.value);

      const eventName = this.el.dataset.event
      const sensorId = this.el.dataset.sensor_id;
      const attributeId = this.el.dataset.attribute_id;

      const payload = {
        sensor_id: sensorId,
        attribute_id: attributeId,
        value: event.target.value
      };

      this.pushEvent(eventName, payload);
    })
  }
}

Hooks.ResizeDetection = {
  isResizing() {
    const mainElement = document.getElementById("main");
    if (!mainElement) return false;
    return mainElement.classList.contains('resizing');
  },
  mounted() {
    //logger.log("Hooks.ResizeDetection", "ResizeDetection Mounted!");

    let resizeStartTime = 0;
    let resizeTotalDuration = 0;
    let isResizing = false;

    window.addEventListener('resize', function () {
      //logger.log("Hooks.ResizeDetection", 'Resize detected!');
      if (!isResizing) {
        isResizing = true
        resizeStartTime = performance.now();
        document.querySelector("body").classList.add('resizing');
        //logger.log("Hooks.ResizeDetection", 'Resize: ', this.document.getElementById("main").classList);
      }
    }, { passive: true });

    window.addEventListener('resizeend', function () {
      //logger.log("Hooks.ResizeDetection", 'Resizeend detected!');

      if (isResizing) {
        isResizing = false
        const resizeEndTime = performance.now();
        const resizeDuration = resizeEndTime - resizeStartTime
        resizeTotalDuration += resizeDuration
        //logger.log("Hooks.ResizeDetection", `Resize duration: ${resizeDuration.toFixed(2)}ms, Total duration: ${resizeTotalDuration.toFixed(2)}ms`);
        document.querySelector("body").classList.remove('resizing');
        //logger.log("Hooks.ResizeDetection", 'Resizeendt: ', this.document.getElementById("main").classList);

        // redraw sparklines
        //new SimpleSparkLineChart('.sparkline');
      }

    }, { passive: true });

    let resizeTimer;
    window.addEventListener('resize', function () {
      clearTimeout(resizeTimer);
      resizeTimer = setTimeout(function () {
        window.dispatchEvent(new Event('resizeend'));
      }, 50);
    }, { passive: true });

  },
  destroyed() {
    logger.log("Hooks.ResizeDetection", "ResizeDetection Destroyed!");
  }
}

Hooks.ConnectionHandler = {
  disconnected(event) {
    logger.log("Hooks.ConnectionHandler", "disconnected", event);
  },
  connected(event) {
    logger.log("Hooks.ConnectionHandler", "connected", event);
  }
}

// CompositeMeasurementHandler hook - receives high-frequency sensor data via ViewerDataChannel
// and dispatches it as window events for Svelte components to consume.
//
// Data path: PriorityLens → PubSub → ViewerDataChannel → sensor_batch → here → CustomEvent → Svelte
// Seed data (historical) still arrives via LobbyLive push_event (start_async path).
Hooks.CompositeMeasurementHandler = {
  mounted() {
    console.log("[CompositeMeasurementHandler] mounted on element:", this.el.id);

    this._channel = null;
    this._channelSocket = null;

    // Receive a signed viewer token from LobbyLive; use it to join ViewerDataChannel.
    // The channel bypasses the LiveView process for all high-frequency sensor data.
    this.handleEvent("viewer_channel_token", ({ token }) => {
      this._joinViewerChannel(token);
    });

    // Handle seed data for composite views - pushes historical data on view entry
    // Buffer seed events for Svelte components that may not have mounted yet
    window.__compositeSeedBuffer = [];
    window.__compositeSeedReady = false;
    this.handleEvent("composite_seed_data", (event) => {
      const { sensor_id, attribute_id, data } = event;
      if (Array.isArray(data) && data.length > 0) {
        if (window.__compositeSeedReady) {
          window.dispatchEvent(new CustomEvent('accumulator-data-event', {
            detail: { sensor_id, attribute_id, data }
          }));
        } else {
          window.__compositeSeedBuffer.push({ sensor_id, attribute_id, data });
        }
      }
    });

    this._onComponentReady = () => {
      const buf = window.__compositeSeedBuffer || [];
      window.__compositeSeedReady = true;
      window.__compositeSeedBuffer = [];
      buf.forEach(event => {
        window.dispatchEvent(new CustomEvent('accumulator-data-event', {
          detail: event
        }));
      });
    };
    window.addEventListener('composite-component-ready', this._onComponentReady);

    // Handle attention changes for attention radar mode
    this.handleEvent("attention_changed", (event) => {
      window.dispatchEvent(new CustomEvent('attention-changed-event', { detail: event }));
    });

    // Forward graph node hover events to server for attention boost
    this._onGraphHover = (e) => {
      const { sensor_id, action } = e.detail;
      if (action === "enter") {
        this.pushEvent("graph_hover_enter", { sensor_id });
      } else {
        this.pushEvent("graph_hover_leave", { sensor_id });
      }
    };
    window.addEventListener("graph-hover-sensor", this._onGraphHover);
  },

  // Join the ViewerDataChannel on the /socket WebSocket using the signed token.
  // Registers channel event handlers for real-time batch delivery.
  _joinViewerChannel(token) {
    if (this._channel) {
      this._channel.leave();
      this._channel = null;
    }
    if (this._channelSocket) {
      this._channelSocket.disconnect();
      this._channelSocket = null;
    }

    const socket = new Socket("/socket", { params: { token: window.userSocketToken || "" } });
    socket.connect();
    this._channelSocket = socket;

    const channel = socket.channel(`viewer:data:${token}`, {});
    this._channel = channel;

    // Batched sensor data: %{batch: %{sensor_id => %{attr_id => measurement}}}
    channel.on("sensor_batch", ({ batch }) => {
      this._dispatchBatch(batch);
    });

    // Digest data: %{digests: %{sensor_id => %{attr_id => %{count, avg, min, max, latest}}}}
    channel.on("sensor_digest", ({ digests }) => {
      for (const [sensorId, attributes] of Object.entries(digests)) {
        for (const [attrId, stats] of Object.entries(attributes)) {
          if (stats.latest != null) {
            window.dispatchEvent(new CustomEvent('composite-measurement-event', {
              detail: {
                sensor_id: sensorId,
                attribute_id: attrId,
                payload: stats.latest,
                timestamp: Date.now()
              }
            }));
          }
        }
      }
    });

    channel.join()
      .receive("ok", () => {
        console.log("[CompositeMeasurementHandler] ViewerDataChannel joined");
      })
      .receive("error", (resp) => {
        console.error("[CompositeMeasurementHandler] ViewerDataChannel join failed", resp);
      });
  },

  // Dispatch measurements from a sensor_batch to Svelte via CustomEvents.
  // Handles single measurements, lists (high-freq), and delta-encoded ECG.
  // Filters attributes by view type to avoid flooding the browser in composite views.
  _dispatchBatch(batch) {
    const elId = this.el.id;
    const isGraphView = elId.startsWith('lobby-graph');

    // Per-view attribute allowlist — only dispatch what the current view needs.
    // null means "dispatch all" (graph views need all attrs for activity pulses + MIDI).
    const ATTR_FILTER = {
      'composite-ecg': new Set(['ecg']),
      'composite-heartrate': new Set(['heartrate', 'hr']),
      'composite-respiration': new Set(['respiration', 'breathing_sync']),
      'composite-hrv': new Set(['hrv', 'hrv_sync']),
      'composite-battery': new Set(['battery']),
      'composite-imu': new Set(['imu']),
      'composite-location': new Set(['geolocation']),
      'composite-skeleton': new Set(['skeleton']),
      'composite-gaze': new Set(['eye_gaze', 'eye_aperture', 'eye_blink', 'eye_worn']),
      'avatar-splat-container': new Set(['imu', 'quaternion', 'euler', 'heartrate', 'hr', 'respiration']),
    };
    const allowedAttrs = ATTR_FILTER[elId] || null;

    for (const [sensorId, attributes] of Object.entries(batch)) {
      const activityAttrIds = isGraphView ? [] : null;

      for (const [attrId, measurement] of Object.entries(attributes)) {
        if (!measurement) continue;

        // Skip attributes not relevant for this view (composite views only)
        if (allowedAttrs && !allowedAttrs.has(attrId)) continue;

        if (measurement.__delta_encoded__) {
          if (isDeltaEncoded(measurement)) {
            const samples = decodeECG(measurement.data);
            if (samples) {
              for (const s of samples) {
                window.dispatchEvent(new CustomEvent('composite-measurement-event', {
                  detail: { sensor_id: sensorId, attribute_id: attrId, payload: s.payload, timestamp: s.timestamp }
                }));
              }
            }
          }
        } else if (Array.isArray(measurement)) {
          for (const item of measurement) {
            window.dispatchEvent(new CustomEvent('composite-measurement-event', {
              detail: { sensor_id: sensorId, attribute_id: attrId, payload: item.payload, timestamp: item.timestamp }
            }));
          }
        } else {
          window.dispatchEvent(new CustomEvent('composite-measurement-event', {
            detail: { sensor_id: sensorId, attribute_id: attrId, payload: measurement.payload, timestamp: measurement.timestamp }
          }));
        }

        if (isGraphView && activityAttrIds) activityAttrIds.push(attrId);
      }

      // Graph activity event: one per sensor per batch (not per attribute)
      if (isGraphView && activityAttrIds && activityAttrIds.length > 0) {
        window.dispatchEvent(new CustomEvent('graph-activity-event', {
          detail: { sensor_id: sensorId, attribute_ids: activityAttrIds, timestamp: Date.now() }
        }));
      }
    }
  },

  destroyed() {
    console.log("[CompositeMeasurementHandler] destroyed");
    if (this._channel) {
      this._channel.leave();
      this._channel = null;
    }
    if (this._channelSocket) {
      this._channelSocket.disconnect();
      this._channelSocket = null;
    }
    if (this._onComponentReady) {
      window.removeEventListener('composite-component-ready', this._onComponentReady);
    }
    if (this._onGraphHover) {
      window.removeEventListener("graph-hover-sensor", this._onGraphHover);
    }
    window.__compositeSeedReady = false;
    window.__compositeSeedBuffer = [];
  }
}

// SensorGridHook — joins ViewerDataChannel for the sensors grid view and delivers
// high-frequency sensor batch data directly to DOM without touching the LobbyLive process.
//
// Data path: ViewerDataChannel → sensor_batch → here → measurements-batch-event → SensorDataAccumulator
//
// The hook also tells the channel which sensors are currently visible (from VirtualScrollHook
// via a sensor-range-changed CustomEvent), so the channel only pushes data for those sensors.
Hooks.SensorGridHook = {
  mounted() {
    this._channel = null;

    // Receive the signed viewer token from LobbyLive and join the channel.
    this.handleEvent("viewer_channel_token", ({ token }) => {
      this._joinViewerChannel(token);
    });

    // Listen for visible range changes dispatched by VirtualScrollHook.
    this._onRangeChanged = (e) => {
      const { startIndex, endIndex } = e.detail;
      const gridEl = document.getElementById("sensor-virtual-scroll");
      if (!gridEl) return;

      let sensorIds = [];
      try {
        sensorIds = JSON.parse(gridEl.dataset.sensorIds || "[]");
      } catch (_) {}

      const visibleIds = sensorIds.slice(startIndex, endIndex);
      if (this._channel) {
        this._channel.push("set_visible_sensors", { sensor_ids: visibleIds });
      }
    };
    window.addEventListener("sensor-range-changed", this._onRangeChanged);
  },

  destroyed() {
    window.removeEventListener("sensor-range-changed", this._onRangeChanged);
    if (this._channel) {
      this._channel.leave();
      this._channel = null;
    }
    if (this._channelSocket) {
      this._channelSocket.disconnect();
      this._channelSocket = null;
    }
  },

  _joinViewerChannel(token) {
    if (this._channel) {
      this._channel.leave();
      this._channel = null;
    }
    if (this._channelSocket) {
      this._channelSocket.disconnect();
      this._channelSocket = null;
    }

    const socket = new Socket("/socket", { params: { token: window.userSocketToken || "" } });
    socket.connect();
    this._channelSocket = socket;

    const channel = socket.channel(`viewer:data:${token}`, {});

    channel.on("sensor_batch", ({ batch }) => {
      this._dispatchBatch(batch);
    });

    channel.on("sensor_digest", ({ digests }) => {
      // Digests arrive at low/minimal quality — dispatch same event shape
      // but with a single-item attributes array holding the latest digest value.
      for (const [sensorId, attrs] of Object.entries(digests)) {
        const attrList = Object.entries(attrs).map(([attrId, digest]) => ({
          attribute_id: attrId,
          payload: digest.latest ?? digest,
          timestamp: Date.now(),
        }));
        if (attrList.length > 0) {
          window.dispatchEvent(new CustomEvent("measurements-batch-event", {
            detail: { sensor_id: sensorId, attributes: attrList },
          }));
        }
      }
    });

    channel.join()
      .receive("ok", () => {
        console.log("[SensorGridHook] ViewerDataChannel joined");
        this._channel = channel;
        // Trigger initial visible sensor report
        const gridEl = document.getElementById("sensor-virtual-scroll");
        if (gridEl) {
          gridEl.dispatchEvent(new CustomEvent("force-range-report"));
        }
      })
      .receive("error", (resp) => {
        console.error("[SensorGridHook] join failed", resp);
      });
  },

  _dispatchBatch(batch) {
    for (const [sensorId, attributes] of Object.entries(batch)) {
      const attrList = [];
      for (const [attrId, data] of Object.entries(attributes)) {
        const items = Array.isArray(data) ? data : [data];
        for (const item of items) {
          if (item != null && item.payload !== undefined) {
            const m = { attribute_id: attrId, payload: item.payload, timestamp: item.timestamp };
            if (item.event !== undefined) m.event = item.event;
            attrList.push(m);
          }
        }
        if (attrId === "button") {
          this._handleButtonEvents(sensorId, items);
        }
      }
      if (attrList.length > 0) {
        window.dispatchEvent(new CustomEvent("measurements-batch-event", {
          detail: { sensor_id: sensorId, attributes: attrList },
        }));
      }
    }
  },

  // Button colors matching server-side @button_colors
  _buttonColors: {
    1: "#ef4444", 2: "#f97316", 3: "#eab308", 4: "#22c55e",
    5: "#14b8a6", 6: "#3b82f6", 7: "#6366f1", 8: "#a855f7"
  },

  _handleButtonEvents(sensorId, items) {
    for (const item of items) {
      if (item == null || item.event == null) continue;
      const btnId = parseInt(item.payload, 10);
      if (isNaN(btnId) || btnId < 1 || btnId > 8) continue;

      if (item.event === "press") {
        this._triggerButtonVibrate(sensorId, btnId, item.timestamp);
        this._flashButtonIndicator(sensorId, btnId);
      }
    }
  },

  _triggerButtonVibrate(sensorId, btnId, timestamp) {
    // Update vibrate element data attributes for the press event
    const vibrateEl = document.getElementById(`vibrate_${sensorId}_button`);
    if (vibrateEl) {
      vibrateEl.dataset.value = String(btnId);
      vibrateEl.dataset.event = "press";
      vibrateEl.dataset.timestamp = String(timestamp);
    }

    // Vibrate
    const duration = btnId * 100;
    if (navigator.vibrate) navigator.vibrate(duration);

    // Play sound using the Vibrate hook's audio logic
    this._playButtonSound(btnId);
  },

  // Flash timers per sensor+button to auto-reset
  _flashTimers: {},

  _flashButtonIndicator(sensorId, btnId) {
    const vibrateEl = document.getElementById(`vibrate_${sensorId}_button`);
    if (!vibrateEl) return;

    const indicators = vibrateEl.querySelectorAll("div[style]");
    const el = indicators[btnId - 1];
    if (!el) return;

    const color = this._buttonColors[btnId];
    el.style.cssText = `background-color: ${color}; color: white; box-shadow: 0 0 12px 2px ${color}, 0 0 4px 1px ${color}; transform: scale(0.9); transition: all 0.1s;`;

    // Reset after 300ms
    const key = `${sensorId}_${btnId}`;
    if (this._flashTimers[key]) clearTimeout(this._flashTimers[key]);
    this._flashTimers[key] = setTimeout(() => {
      el.style.cssText = "background-color: #4b5563; color: #9ca3af; box-shadow: none; transform: scale(1); transition: all 0.3s;";
      delete this._flashTimers[key];
    }, 300);
  },

  _buttonAudioCtx: null,

  _playButtonSound(btnId) {
    try {
      if (!this._buttonAudioCtx) {
        this._buttonAudioCtx = new (window.AudioContext || window.webkitAudioContext)();
      }
      const ctx = this._buttonAudioCtx;
      const now = ctx.currentTime;
      const freqs = { 1: 261.6, 2: 293.7, 3: 329.6, 4: 392.0, 5: 440.0, 6: 523.3, 7: 587.3, 8: 659.3 };
      const baseFreq = freqs[btnId] || 392.0;

      const osc1 = ctx.createOscillator();
      const osc2 = ctx.createOscillator();
      const gain = ctx.createGain();
      const filter = ctx.createBiquadFilter();

      osc1.connect(filter); osc2.connect(filter);
      filter.connect(gain); gain.connect(ctx.destination);

      osc1.type = "triangle"; osc2.type = "sine";
      osc1.frequency.setValueAtTime(baseFreq * 1.5, now);
      osc1.frequency.exponentialRampToValueAtTime(baseFreq * 0.8, now + 0.08);
      osc2.frequency.setValueAtTime(baseFreq * 3, now);
      osc2.frequency.exponentialRampToValueAtTime(baseFreq * 1.6, now + 0.06);

      filter.type = "lowpass";
      filter.frequency.setValueAtTime(2000, now);
      filter.frequency.exponentialRampToValueAtTime(400, now + 0.15);
      filter.Q.value = 2;

      gain.gain.setValueAtTime(0, now);
      gain.gain.linearRampToValueAtTime(0.25, now + 0.01);
      gain.gain.exponentialRampToValueAtTime(0.08, now + 0.1);
      gain.gain.exponentialRampToValueAtTime(0.001, now + 0.25);

      osc1.start(now); osc2.start(now);
      osc1.stop(now + 0.3); osc2.stop(now + 0.3);
    } catch (_) {}
  },
};

// FooterToolbar hook - floating pill with popover for desktop sensor controls
Hooks.FooterToolbar = {
  mounted() {
    this.isExpanded = false;
    this._setup();
  },

  updated() {
    this._setup();
    this._applyState();
  },

  _setup() {
    this.pillBtn = this.el.querySelector('#footer-pill-toggle');
    this.popover = this.el.querySelector('#footer-popover');

    if (this.pillBtn && !this.pillBtn._ftBound) {
      this.pillBtn._ftBound = true;
      this.pillBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        e.stopImmediatePropagation();
        this._lastToggle = Date.now();
        this.isExpanded = !this.isExpanded;
        this._applyState();
      });
    }

    if (!this._docBound) {
      this._docBound = true;
      document.addEventListener('click', (e) => {
        // Guard: on Android touch devices, the document click can fire
        // in the same frame as the button click. Skip if < 100ms since toggle.
        if (this._lastToggle && Date.now() - this._lastToggle < 100) return;
        if (this.isExpanded && !this.el.contains(e.target)) {
          this.isExpanded = false;
          this._applyState();
        }
      });
    }
  },

  _applyState() {
    if (!this.popover || !this.pillBtn) return;
    if (this.isExpanded) {
      this.popover.classList.remove('hidden');
      this.pillBtn.classList.add('bg-blue-600', 'text-white', 'border-blue-500');
      this.pillBtn.classList.remove('bg-gray-800', 'text-gray-400', 'border-gray-600');
    } else {
      this.popover.classList.add('hidden');
      this.pillBtn.classList.remove('bg-blue-600', 'text-white', 'border-blue-500');
      this.pillBtn.classList.add('bg-gray-800', 'text-gray-400', 'border-gray-600');
    }
  },

  destroyed() {
    this.isExpanded = false;
  }
}

// TimeDiff hook - displays relative time that updates when data-timestamp changes
Hooks.TimeDiff = {
  mounted() {
    this.startTime = parseInt(this.el.dataset.timestamp);
    this.updateDisplay();
    this.startTimer();

    // Use MutationObserver to detect attribute changes since LiveView
    // may not trigger updated() for attribute-only changes
    this.observer = new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        if (mutation.type === 'attributes' && mutation.attributeName === 'data-timestamp') {
          const newTimestamp = parseInt(this.el.dataset.timestamp);
          if (newTimestamp !== this.startTime) {
            this.startTime = newTimestamp;
            this.clearTimer();
            this.updateDisplay();
            this.startTimer();
          }
        }
      }
    });
    this.observer.observe(this.el, { attributes: true });
  },

  updated() {
    const newTimestamp = parseInt(this.el.dataset.timestamp);
    if (newTimestamp !== this.startTime) {
      this.startTime = newTimestamp;
      this.clearTimer();
      this.updateDisplay();
      this.startTimer();
    }
  },

  destroyed() {
    this.clearTimer();
    if (this.observer) {
      this.observer.disconnect();
    }
  },

  clearTimer() {
    if (this.timerInterval) {
      clearInterval(this.timerInterval);
      this.timerInterval = null;
    }
  },

  startTimer() {
    const diff = Date.now() - this.startTime;
    // Choose interval based on how old the timestamp is
    const interval = diff < 1000 ? 100 : diff < 60000 ? 1000 : 60000;
    this.timerInterval = setInterval(() => this.updateDisplay(), interval);
  },

  updateDisplay() {
    const diff = Date.now() - this.startTime;
    let text;

    if (diff < 1000) {
      text = `${diff.toFixed(0)} ms`;
    } else if (diff < 60000) {
      text = `${(diff / 1000).toFixed(1)} secs`;
    } else if (diff < 3600000) {
      const mins = Math.floor(diff / 60000);
      text = `${mins} min${mins > 1 ? 's' : ''}`;
    } else if (diff < 86400000) {
      text = `${Math.floor(diff / 3600000)} hours`;
    } else {
      text = `${Math.floor(diff / 86400000)} days`;
    }

    this.el.textContent = text;
  }
}

// SystemMetricsRefresh hook - triggers periodic refresh of system metrics display
Hooks.SystemMetricsRefresh = {
  mounted() {
    this.interval = setInterval(() => {
      // pushEventTo targets the LiveComponent by its phx-target (the element itself)
      this.pushEventTo(this.el, "refresh", {});
    }, 5000);
  },
  destroyed() {
    if (this.interval) {
      clearInterval(this.interval);
    }
  }
}

// PulsatingLogo hook - CSS heart animation based on system load
// Uses pure CSS animation that works reliably on fly.io and other platforms
Hooks.PulsatingLogo = {
  mounted() {
    this.currentMultiplier = 1.0;
    this.currentLoadLevel = 'normal';

    // Apply initial styles
    this.applyHeartStyles();
    this.updateFromMetrics();

    this.observer = new MutationObserver(() => {
      this.updateFromMetrics();
    });

    const metricsEl = document.querySelector('[id="system-metrics"]');
    if (metricsEl) {
      this.observer.observe(metricsEl, { childList: true, subtree: true, characterData: true });
    }

    this.refreshInterval = setInterval(() => this.updateFromMetrics(), 2000);
  },

  applyHeartStyles() {
    // Inject CSS for heart animation if not already present
    if (!document.getElementById('system-pulse-heart-styles')) {
      const style = document.createElement('style');
      style.id = 'system-pulse-heart-styles';
      style.textContent = `
        .system-pulse-heart {
          display: inline-flex;
          align-items: center;
          justify-content: center;
          transition: color 0.3s ease;
        }
        .system-pulse-heart svg {
          animation: heartbeat var(--heartbeat-duration, 2s) ease-in-out infinite;
        }
        @keyframes heartbeat {
          0%, 100% { transform: scale(1); }
          14% { transform: scale(1.15); }
          28% { transform: scale(1); }
          42% { transform: scale(1.1); }
          56% { transform: scale(1); }
        }
        .system-pulse-heart.load-normal { color: #22c55e; --heartbeat-duration: 3s; }
        .system-pulse-heart.load-elevated { color: #eab308; --heartbeat-duration: 1.5s; }
        .system-pulse-heart.load-high { color: #f97316; --heartbeat-duration: 0.8s; }
        .system-pulse-heart.load-critical { color: #ef4444; --heartbeat-duration: 0.4s; }
        .system-pulse-heart:hover { opacity: 0.8; }
      `;
      document.head.appendChild(style);
    }
  },

  updateFromMetrics() {
    const metricsEl = document.querySelector('[id="system-metrics"]');
    if (!metricsEl) return;

    const metricsText = metricsEl.textContent || '';

    // Extract load level from the text (NORMAL, ELEVATED, HIGH, CRITICAL)
    const loadMatch = metricsText.match(/\b(normal|elevated|high|critical)\b/i);
    if (loadMatch) {
      const newLevel = loadMatch[1].toLowerCase();
      if (newLevel !== this.currentLoadLevel) {
        this.currentLoadLevel = newLevel;
        this.updateHeartState(newLevel);
      }
    }

    // Also update based on multiplier for fine-grained control
    const multiplierMatch = metricsText.match(/x\s*([\d.]+)/);
    if (multiplierMatch) {
      const newMultiplier = parseFloat(multiplierMatch[1]);
      if (!isNaN(newMultiplier)) {
        this.currentMultiplier = newMultiplier;
      }
    }
  },

  updateHeartState(level) {
    // Remove all load classes
    this.el.classList.remove('load-normal', 'load-elevated', 'load-high', 'load-critical');
    // Add current load class
    this.el.classList.add(`load-${level}`);
  },

  destroyed() {
    if (this.refreshInterval) {
      clearInterval(this.refreshInterval);
    }
    if (this.observer) {
      this.observer.disconnect();
    }
  }
}

// MobileMenu hook removed — use BaseHooks.MobileMenu from hooks.js
// (has justOpened flag + touchend handling for mobile touch devices)

Hooks.SensorDataAccumulator = {

  workerEventListener(event) {
    const { type, data } = event;
    logger.log("Hooks.SensorDataAccumulator", "WORKER event", type, data);

    const workerEvent = new CustomEvent('storage-worker-event', { id: data.sensor_id + "_" + data.attribute_id, detail: event.data });
    window.dispatchEvent(workerEvent);
  },

  mounted() {
    //workerStorage.postMessage({ type: 'clear-data', data: { sensor_id: this.el.dataset.sensor_id, attribute_id: this.el.dataset.attribute_id } });


    // handleGetAllLatestTimestamps().then((result) => {
    //   console.log("last timestamps for all keys:", result);
    // });

    // make sure we wait for server seed
    this.el.dataset.seeding = true;
    handleGetLastTimestamp(this.el.dataset.sensor_id, this.el.dataset.attribute_id).then((result) => {
      console.log("Last timestamp for ", this.el.dataset.sensor_id, this.el.dataset.attribute_id, result);

      const payload = {
        "sensor_id": this.el.dataset.sensor_id,
        "attribute_id": this.el.dataset.attribute_id,
        "from": result,
        "to": null,
        "limit": null
      };

      logger.log("Hooks.SensorDataAccumulator", "pushEvent seeddata", payload, result);

      this.handleEvent("seeddata", (seed) => {
        console.log("Hooks.SensorDataAccumulator", "seed-data", seed);

        let identifier_seed = seed.sensor_id + "_" + seed.attribute_id;

        if (seed.sensor_id == this.el.dataset.sensor_id && seed.attribute_id == this.el.dataset.attribute_id) {

          handleAppendAndReadData(seed.sensor_id, seed.attribute_id, seed).then((result) => {
            logger.log("Hooks.SensorDataAccumulator", "handleAppendAndReadData measurement", seed.sensor_id, seed.attribute_id, "Seed length: ", seed.length, "Result length: ", result.length);
            const seedEvent = new CustomEvent('seeddata-event', { id: identifier_seed, detail: { sensor_id: seed.sensor_id, attribute_id: seed.attribute_id, data: result } });
            window.dispatchEvent(seedEvent);
            this.el.dataset.seeding = false;
          });

          // workerStorage.postMessage({ type: 'seed-data', data: { sensor_id: this.el.dataset.sensor_id, attribute_id: this.el.dataset.attribute_id, seedData: seed.data } });

        }
      });

      this.pushEvent("request-seed-data", payload);
    });


    this.handleEvent("clear-attribute", (e) => {

      this.el.dataset.seeding = true;

      logger.log("Hooks.SensorDataAccumulator", "clear-attribute", e.sensor_id, e.attribute_id);
      handleClearData(e.sensor_id, e.attribute_id).then((result) => {
        const seedEvent = new CustomEvent('seeddata-event', { id: e.sensor_id + '_' + e.attribute_id, detail: { sensor_id: e.sensor_id, attribute_id: e.attribute_id, data: [] } });
        workerStorage.postMessage({ type: 'clear-data', data: { sensor_id: this.el.dataset.sensor_id, attribute_id: this.el.dataset.attribute_id } });
        window.dispatchEvent(seedEvent);

        this.el.dataset.seeding = false;
      });
    }
    );

    var hookElement = this.el;

    // Listen for batch measurements delivered by SensorGridHook via ViewerDataChannel.
    // Uses a global window event so data bypasses the LobbyLive process entirely.
    this._onMeasurementsBatch = (e) => {
      const event = e.detail;
      if (hookElement.dataset.seeding !== true && event.sensor_id == hookElement.dataset.sensor_id) {
        let uniqueAttributeIds = [...new Set(event.attributes.map(a => a.attribute_id))];
        uniqueAttributeIds.forEach(attributeId => {
          if (attributeId == hookElement.dataset.attribute_id) {
            let relevantAttributes = event.attributes.filter(a => a.attribute_id === attributeId);
            logger.log("Hooks.SensorDataAccumulator", "measurements-batch-event BATCH", event.sensor_id, attributeId, relevantAttributes.length);
            const accumulatorEvent = new CustomEvent('accumulator-data-event', { detail: { sensor_id: event.sensor_id, attribute_id: attributeId, data: relevantAttributes } });
            window.dispatchEvent(accumulatorEvent);
            handleAppendData(event.sensor_id, attributeId, relevantAttributes).then((result) => {
              logger.log("Hooks.SensorDataAccumulator", "handleAppendData measurements_batch", event.sensor_id, attributeId, result);
            });
          }
        });
      }
    };
    window.addEventListener("measurements-batch-event", this._onMeasurementsBatch);

    resizeElements();
  },

  destroyed() {
    if (this._onMeasurementsBatch) {
      window.removeEventListener("measurements-batch-event", this._onMeasurementsBatch);
    }
  },



  updated() {

  }
}
// add one listener for all components
window.addEventListener('worker-requesthandler-event', function (event) {
  logger.log("Hooks.SensorDataAccumulator", 'worker-requesthandler-event', event.type, event.detail);
  workerStorage.postMessage({ type: event.detail.type, data: event.detail.data });
}, false);



function resizeElements() {
  const allSparklines = document.querySelectorAll('.resizeable');

  allSparklines.forEach(element => {
    const parent = element.parentElement;
    if (!parent) {
      console.warn("Parent element not found for", element);
      return;
    }

    const computedStyle = getComputedStyle(parent);

    // Get padding and margin values
    const paddingLeft = parseFloat(computedStyle.paddingLeft) || 0;
    const paddingRight = parseFloat(computedStyle.paddingRight) || 0;
    const paddingTop = parseFloat(computedStyle.paddingTop) || 0;
    const paddingBottom = parseFloat(computedStyle.paddingBottom) || 0;

    const marginLeft = parseFloat(computedStyle.marginLeft) || 0;
    const marginRight = parseFloat(computedStyle.marginRight) || 0;
    const marginTop = parseFloat(computedStyle.marginTop) || 0;
    const marginBottom = parseFloat(computedStyle.marginBottom) || 0;

    // Calculate the inner width and height by subtracting padding and margins.
    const parentWidth = parent.offsetWidth - paddingLeft - paddingRight - marginLeft - marginRight;
    const parentHeight = parent.offsetHeight - paddingTop - paddingBottom - marginTop - marginBottom;

    // Calculate the available with based on padding and margin
    const availableWidth = parentWidth;
    const availableHeight = parentHeight;

    element.setAttribute('width', availableWidth);
    logger.log("Element Resizer", element.id, availableWidth, availableHeight, element.getAttribute("width"));
  });
}

window.addEventListener('resizeend', resizeElements, { passive: true });


// Also set it up on DOMContentLoaded, for correct initial loading.
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', resizeElements);
  //initSparklineWasm();r
} else {
  // initial graph resize
  resizeElements();
}



window.addEventListener("phx:live_reload:attached", ({ detail: reloader }) => {
  // Enable server log streaming to client.
  // Disable with reloader.disableServerLogs()
  reloader.enableServerLogs()
  window.liveReloader = reloader
  let keyDown
  window.addEventListener("keydown", (event) => keyDown = event.key)
  window.addEventListener("keyup", (_) => keyDown = null)
  window.addEventListener("click", (event) => {
    if (keyDown === "c") {
      event.preventDefault()
      event.stopImmediatePropagation()
      reloader.openEditorAtCaller(event.target)
    } else if (keyDown === "d") {
      event.preventDefault()
      event.stopImmediatePropagation()
      reloader.openEditorAtDef(event.target)
    }
  })
})


workerStorage.addEventListener('message', Hooks.SensorDataAccumulator.workerEventListener);

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

// Merge all hooks: Svelte component hooks, base hooks from hooks.js (includes MediaPlayerHook), and app.js hooks
let mergedHooks = { ...getHooks(Components), ...BaseHooks, ...Hooks };

let liveSocket = new LiveSocket("/live", Socket, { hooks: mergedHooks, params: { _csrf_token: csrfToken } })

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" })
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()
liveSocket.disableDebug();

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// Override reloadWithJitter to prevent unnecessary full page reloads.
// Default LiveView behavior: on socket close (code 1000), immediately disconnects
// the socket and schedules window.location.reload() after 5-10s jitter.
// The disconnect() call is fatal — it prevents the natural reconnection that would
// otherwise remount views without a page reload.
// Our override: don't disconnect, give the socket 20s to reconnect naturally.
// Views will rejoin with new server processes — no page reload needed.
const _origReloadWithJitter = liveSocket.reloadWithJitter.bind(liveSocket);
liveSocket.reloadWithJitter = function(view, log) {
  clearTimeout(this.reloadWithJitterTimer);
  // DON'T call this.disconnect() — let the socket reconnect naturally
  this.reloadWithJitterTimer = setTimeout(() => {
    if (view.isDestroyed() || view.isConnected()) {
      return; // View recovered — cancel reload
    }
    // Server didn't come back in 20s — fall back to hard reload
    _origReloadWithJitter(view, log);
  }, 20000);
};

// Wire up connection monitor to watch LiveSocket and control the offline overlay
connectionMonitor.watchLiveSocket(liveSocket);

connectionMonitor.subscribe((state) => {
  const overlay = document.getElementById('offline-overlay');
  const message = document.getElementById('offline-message');
  const bufferCount = document.getElementById('offline-buffer-count');
  const bufferNum = document.getElementById('offline-buffer-num');
  if (!overlay) return;

  const { STATES } = connectionMonitor;

  if (state.status === STATES.ONLINE) {
    // Slide out, then hide
    overlay.classList.add('translate-y-[-100%]');
    setTimeout(() => overlay.classList.add('hidden'), 300);
  } else {
    // Show and slide in
    overlay.classList.remove('hidden');
    requestAnimationFrame(() => {
      overlay.classList.remove('translate-y-[-100%]');
    });

    if (state.status === STATES.SYNCING) {
      message.textContent = 'Syncing buffered data\u2026';
    } else if (state.status === STATES.OFFLINE) {
      message.textContent = 'Server unreachable \u2013 BLE data is being buffered';
    } else {
      message.textContent = 'Reconnecting\u2026';
    }

    if (state.bufferedCount > 0) {
      bufferCount.classList.remove('hidden');
      bufferNum.textContent = state.bufferedCount;
    } else {
      bufferCount.classList.add('hidden');
    }
  }
});

// Re-apply overlay state after LiveView navigation replaces the DOM
window.addEventListener('phx:page-loading-stop', () => {
  if (connectionMonitor.state.status !== connectionMonitor.STATES.ONLINE) {
    connectionMonitor.notify();
  }
});
