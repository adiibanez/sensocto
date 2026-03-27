// ButtplugBridge — LiveView hook that bridges buttplug.io devices into Sensocto sensors.
//
// Uses buttplug-js v4 API:
//   - ButtplugBrowserWebsocketClientConnector for WebSocket transport
//   - device.runOutput(cmd) for actuator control
//   - device.hasOutput(OutputType.Vibrate) for capability detection
//
// Lifecycle:
//   1. User clicks "Connect to Intiface" → hook calls connect()
//   2. buttplug-js connects to ws://127.0.0.1:12345 (Intiface Central)
//   3. On DeviceAdded → join SensorDataChannel for that device, register attributes
//   4. Sensor readings (battery, etc.) → channel.push("measurement", ...)
//   5. channel.on("device_command") → translate to buttplug runOutput commands
//   6. On DeviceRemoved or disconnect → clean up channels

import {
  ButtplugClient,
  ButtplugBrowserWebsocketClientConnector,
  OutputType,
  DeviceOutputValueConstructor,
  DeviceOutputPositionWithDurationConstructor,
} from "buttplug";
import { Socket } from "phoenix";

const DEFAULT_INTIFACE_URL = "ws://127.0.0.1:12345";
const SENSOR_POLL_INTERVAL = 5000; // Poll battery every 5s

export const ButtplugBridgeHook = {
  mounted() {
    this.client = null;
    this.connector = null;
    this.devices = new Map(); // deviceIndex → { device, channel, pollTimer, sensorId }
    this.channelSocket = null;
    this.status = "disconnected";
    this.bearerToken = this.el.dataset.bearerToken || "missing";
    this.connectorId = `buttplug-${Date.now()}`;

    // Listen for LiveView events
    this.handleEvent("buttplug_connect", ({ url }) => {
      this.connect(url || DEFAULT_INTIFACE_URL);
    });

    this.handleEvent("buttplug_disconnect", () => {
      this.disconnect();
    });

    this.handleEvent("buttplug_start_scan", () => {
      this.startScanning();
    });

    this.handleEvent("buttplug_stop_scan", () => {
      this.stopScanning();
    });

    this.handleEvent("buttplug_send_command", ({ sensor_id, command }) => {
      this.sendDeviceCommand(sensor_id, command);
    });
  },

  destroyed() {
    this.disconnect();
  },

  // --- Connection lifecycle ---

  async connect(url) {
    if (this.client) {
      await this.disconnect();
    }

    this.pushStatus("connecting");

    try {
      this.client = new ButtplugClient("Sensocto");

      this.client.addListener("deviceadded", (device) => this.onDeviceAdded(device));
      this.client.addListener("deviceremoved", (device) => this.onDeviceRemoved(device));
      this.client.addListener("disconnect", () => this.onServerDisconnect());

      // Ensure Phoenix channel socket for sensor data
      this.ensureChannelSocket();

      // v4 API: create connector explicitly, pass to client.connect()
      this.connector = new ButtplugBrowserWebsocketClientConnector(url);
      await this.client.connect(this.connector);
      this.pushStatus("connected");
    } catch (err) {
      console.error("[ButtplugBridge] Connection failed:", err);
      this.pushStatus("error", err.message);
      this.client = null;
      this.connector = null;
    }
  },

  async disconnect() {
    for (const [index, entry] of this.devices.entries()) {
      this.cleanupDevice(index, entry);
    }
    this.devices.clear();

    if (this.client) {
      try {
        await this.client.disconnect();
      } catch (_) {
        // Ignore disconnect errors
      }
      this.client = null;
      this.connector = null;
    }

    if (this.channelSocket) {
      this.channelSocket.disconnect();
      this.channelSocket = null;
    }

    this.pushStatus("disconnected");
  },

  async startScanning() {
    if (!this.client) return;
    try {
      this.pushStatus("scanning");
      await this.client.startScanning();
    } catch (err) {
      console.error("[ButtplugBridge] Scan failed:", err);
    }
  },

  async stopScanning() {
    if (!this.client) return;
    try {
      await this.client.stopScanning();
      this.pushStatus("connected");
    } catch (_) {
      // Ignore
    }
  },

  // --- Device management ---

  onDeviceAdded(device) {
    console.log("[ButtplugBridge] Device added:", device.name, "index:", device.index);

    const sensorId = `buttplug:${device.index}:${device.name.replace(/\s+/g, "_")}`;
    const attributes = this.buildDeviceAttributes(device);
    const capabilities = this.getDeviceCapabilities(device);

    // Join SensorDataChannel for this device
    const channelName = `sensocto:sensor:${sensorId}`;
    const channel = this.channelSocket.channel(channelName, {
      connector_id: this.connectorId,
      connector_name: "Buttplug Bridge",
      sensor_id: sensorId,
      sensor_name: device.displayName || device.name,
      sensor_type: "buttplug",
      attributes: attributes,
      sampling_rate: 10,
      batch_size: 1,
      bearer_token: this.bearerToken,
    });

    channel.join()
      .receive("ok", () => {
        console.log("[ButtplugBridge] Joined channel for", sensorId);

        for (const attr of attributes) {
          channel.push("update_attributes", {
            action: "register",
            attribute_id: attr.attribute_id,
            metadata: {
              attribute_type: attr.attribute_type,
              attribute_id: attr.attribute_id,
              sampling_rate: attr.sampling_rate || 1,
            },
          });
        }
      })
      .receive("error", (resp) => {
        console.error("[ButtplugBridge] Failed to join channel for", sensorId, resp);
      });

    // Listen for commands from server
    channel.on("device_command", (cmd) => {
      this.executeDeviceCommand(device, cmd);
    });

    // Poll battery if supported
    let pollTimer = null;
    if (capabilities.has_battery) {
      pollTimer = setInterval(() => this.pollDeviceSensors(device, sensorId, channel), SENSOR_POLL_INTERVAL);
    }

    this.devices.set(device.index, { device, channel, pollTimer, sensorId });

    // Notify LiveView
    this.pushEvent("buttplug_device_added", {
      device_index: device.index,
      sensor_id: sensorId,
      name: device.displayName || device.name,
      capabilities,
    });
  },

  onDeviceRemoved(device) {
    console.log("[ButtplugBridge] Device removed:", device.name);
    const entry = this.devices.get(device.index);
    if (entry) {
      this.cleanupDevice(device.index, entry);
      this.devices.delete(device.index);
    }

    this.pushEvent("buttplug_device_removed", {
      device_index: device.index,
    });
  },

  onServerDisconnect() {
    console.warn("[ButtplugBridge] Intiface server disconnected");
    for (const [index, entry] of this.devices.entries()) {
      this.cleanupDevice(index, entry);
    }
    this.devices.clear();
    this.client = null;
    this.connector = null;
    this.pushStatus("disconnected");
  },

  cleanupDevice(_index, entry) {
    if (entry.pollTimer) {
      clearInterval(entry.pollTimer);
    }
    if (entry.channel) {
      entry.channel.push("disconnect", {});
      entry.channel.leave();
    }
  },

  // --- Attribute/capability helpers (v4 API) ---

  buildDeviceAttributes(device) {
    const attrs = [];

    if (device.hasOutput(OutputType.Vibrate)) {
      attrs.push({ attribute_id: "vibrate", attribute_type: "numeric", sampling_rate: 10 });
    }
    if (device.hasOutput(OutputType.Rotate)) {
      attrs.push({ attribute_id: "rotate", attribute_type: "numeric", sampling_rate: 10 });
    }
    if (device.hasOutput(OutputType.Position) || device.hasOutput(OutputType.PositionWithDuration)) {
      attrs.push({ attribute_id: "linear", attribute_type: "numeric", sampling_rate: 10 });
    }
    if (device.hasOutput(OutputType.Oscillate)) {
      attrs.push({ attribute_id: "oscillate", attribute_type: "numeric", sampling_rate: 10 });
    }

    // Battery detection — try/catch since not all devices support it
    let hasBattery = false;
    try {
      hasBattery = typeof device.battery === "function";
    } catch (_) {}
    if (hasBattery) {
      attrs.push({ attribute_id: "battery", attribute_type: "battery", sampling_rate: 0.1 });
    }

    attrs.push({ attribute_id: "status", attribute_type: "numeric", sampling_rate: 1 });

    return attrs;
  },

  getDeviceCapabilities(device) {
    let hasBattery = false;
    try {
      hasBattery = typeof device.battery === "function";
    } catch (_) {}

    return {
      vibrate: device.hasOutput(OutputType.Vibrate) ? 1 : 0,
      rotate: device.hasOutput(OutputType.Rotate) ? 1 : 0,
      linear: (device.hasOutput(OutputType.Position) || device.hasOutput(OutputType.PositionWithDuration)) ? 1 : 0,
      oscillate: device.hasOutput(OutputType.Oscillate) ? 1 : 0,
      has_battery: hasBattery,
    };
  },

  // --- Sensor polling ---

  async pollDeviceSensors(device, _sensorId, channel) {
    try {
      const level = await device.battery();
      channel.push("measurement", {
        attribute_id: "battery",
        payload: { level: level, charging: false },
        timestamp: Date.now(),
      });
    } catch (err) {
      console.warn("[ButtplugBridge] Sensor poll error:", err.message);
    }
  },

  // --- Command execution (v4 API) ---

  async sendDeviceCommand(sensorId, command) {
    const entry = [...this.devices.values()].find((e) => e.sensorId === sensorId);
    if (!entry) {
      console.warn("[ButtplugBridge] No device found for sensor", sensorId);
      return;
    }
    await this.executeDeviceCommand(entry.device, command);
  },

  async executeDeviceCommand(device, cmd) {
    try {
      switch (cmd.command) {
        case "vibrate":
          await device.runOutput(new DeviceOutputValueConstructor(OutputType.Vibrate, cmd.speed || 0));
          break;

        case "rotate":
          await device.runOutput(new DeviceOutputValueConstructor(OutputType.Rotate, cmd.speed || 0));
          break;

        case "linear":
          await device.runOutput(
            new DeviceOutputPositionWithDurationConstructor(
              OutputType.PositionWithDuration,
              cmd.position || 0,
              cmd.duration || 500
            )
          );
          break;

        case "oscillate":
          await device.runOutput(new DeviceOutputValueConstructor(OutputType.Oscillate, cmd.speed || 0));
          break;

        case "stop":
          await device.stop();
          break;

        default:
          console.warn("[ButtplugBridge] Unknown command:", cmd.command);
      }
    } catch (err) {
      console.error("[ButtplugBridge] Command execution error:", err);
    }
  },

  // --- Socket helpers ---

  ensureChannelSocket() {
    if (this.channelSocket) return;
    this.channelSocket = new Socket("/socket", {
      params: { token: window.userSocketToken || "" },
    });
    this.channelSocket.connect();
  },

  // --- Status push ---

  pushStatus(status, error) {
    this.status = status;
    this.pushEvent("buttplug_status_changed", {
      status,
      error: error || null,
      device_count: this.devices.size,
    });
  },
};
