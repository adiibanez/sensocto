# Sensocto Three.js/TypeScript SDK

TypeScript client library for connecting to the Sensocto sensor platform, with optional Three.js integration for 3D visualization.

## Features

- Full TypeScript support with strict typing
- Phoenix WebSocket protocol implementation
- Real-time sensor data streaming with backpressure handling
- Video/voice call session management via WebRTC signaling
- Optional Three.js integration for 3D sensor visualization
- Works in both browser and Node.js environments
- ESM and CommonJS builds

## Installation

```bash
# npm
npm install @sensocto/threejs

# yarn
yarn add @sensocto/threejs

# pnpm
pnpm add @sensocto/threejs
```

For Three.js integration (optional):

```bash
npm install three @types/three
```

## Quick Start

### Basic Usage

```typescript
import { SensoctoClient } from "@sensocto/threejs";

// Create and connect
const client = new SensoctoClient({
  serverUrl: "https://your-server.com",
  bearerToken: "your-token",
  connectorName: "My Sensor Hub",
});

await client.connect();

// Register a sensor
const sensor = await client.registerSensor({
  sensorName: "Temperature Sensor",
  sensorType: "temperature",
  attributes: ["celsius", "fahrenheit"],
});

// Send measurements
await sensor.sendMeasurement("celsius", { value: 23.5 });

// Cleanup
await client.disconnect();
```

### Batch Sending with Backpressure

```typescript
const sensor = await client.registerSensor({
  sensorName: "High-frequency Sensor",
  samplingRateHz: 100,
  batchSize: 10,
});

// Handle backpressure from server
sensor.onBackpressure((config) => {
  console.log(`Attention level: ${config.attentionLevel}`);
  console.log(`Recommended batch size: ${config.recommendedBatchSize}`);
});

// Add measurements to batch (auto-flushes based on backpressure)
for (let i = 0; i < 100; i++) {
  await sensor.addToBatch("value", { reading: Math.random() * 100 });
}

// Manual flush if needed
await sensor.flushBatch();
```

### Video/Voice Calls

```typescript
const session = await client.joinCall("room-123", "user-456", {
  displayName: "John Doe",
});

// Listen for call events
session.onEvent((event) => {
  switch (event.type) {
    case "participant_joined":
      console.log("Joined:", event.participant.userId);
      break;
    case "participant_left":
      console.log("Left:", event.userId);
      break;
    case "media_event":
      // Handle WebRTC signaling
      handleMediaEvent(event.data);
      break;
  }
});

// Join the actual call
const { endpointId, participants } = await session.joinCall();

// Get ICE servers for WebRTC
const iceServers = session.rtcIceServers;

// Send WebRTC signaling
await session.sendMediaEvent(sdpOffer);

// Toggle media
await session.toggleAudio(true);
await session.toggleVideo(true);

// Leave call
await session.close();
```

## Three.js Integration

The SDK provides optional Three.js utilities for visualizing sensor data in 3D.

### Basic 3D Visualization

```typescript
import { SensoctoClient } from "@sensocto/threejs";
import { SensorObject3D, SensorDataVisualizer } from "@sensocto/threejs/three";
import * as THREE from "three";

// Set up Three.js scene
const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(75, window.innerWidth / window.innerHeight, 0.1, 1000);
const renderer = new THREE.WebGLRenderer();
renderer.setSize(window.innerWidth, window.innerHeight);
document.body.appendChild(renderer.domElement);

// Create sensor visualization
const sensorObject = new SensorObject3D({
  geometry: new THREE.SphereGeometry(0.5, 32, 32),
  color: 0x00ff00,
  showAttentionLevel: true,
});
scene.add(sensorObject);

// Connect to Sensocto
const client = new SensoctoClient({ serverUrl: "https://your-server.com" });
await client.connect();

const sensor = await client.registerSensor({
  sensorName: "Position Tracker",
  attributes: ["position"],
});

// Update visualization on backpressure changes
sensor.onBackpressure((config) => {
  sensorObject.setAttentionLevel(config.attentionLevel);
});

// Animation loop
function animate() {
  requestAnimationFrame(animate);
  renderer.render(scene, camera);
}
animate();
```

### SensorObject3D API

```typescript
import { SensorObject3D } from "@sensocto/threejs/three";
import { AttentionLevel } from "@sensocto/threejs";

const sensor = new SensorObject3D({
  geometry: new THREE.BoxGeometry(1, 1, 1),
  color: 0x0088ff,
  showAttentionLevel: true,
  attentionColors: {
    [AttentionLevel.None]: 0x00ff00,
    [AttentionLevel.Low]: 0xffff00,
    [AttentionLevel.Medium]: 0xffa500,
    [AttentionLevel.High]: 0xff0000,
  },
});

// Position updates
sensor.setPosition(x, y, z);
sensor.setPositionFromPayload({ x: 1, y: 2, z: 3 });

// Rotation updates
sensor.setRotation(rx, ry, rz);
sensor.setRotationFromPayload({ x: 0, y: Math.PI, z: 0 });

// Visual feedback
sensor.setAttentionLevel(AttentionLevel.Medium);
sensor.setValue(0.75); // Affects scale
sensor.pulse(200, 1.2); // Visual pulse effect
sensor.setColor(0xff0000);
sensor.setEnabled(true);

// Cleanup
sensor.dispose();
```

### SensorDataVisualizer

```typescript
import { SensorDataVisualizer } from "@sensocto/threejs/three";

const visualizer = new SensorDataVisualizer(scene, {
  maxTrailPoints: 100,
  showTrails: true,
  trailColor: 0x00ffff,
  trailOpacity: 0.5,
});

// Bind sensor to object with custom value mapping
visualizer.bindSensor(sensor, sensorObject, {
  position: (value, obj) => {
    const data = value as { x: number; y: number; z: number };
    obj.position.set(data.x, data.y, data.z);
  },
});

// Enable position trail
visualizer.enableTrail(sensorObject);

// Update trails in animation loop
function animate() {
  visualizer.updateAllTrails();
  renderer.render(scene, camera);
  requestAnimationFrame(animate);
}

// Cleanup
visualizer.dispose();
```

## Event Handling

### Connection State

```typescript
client.onConnectionStateChange((state) => {
  switch (state) {
    case ConnectionState.Connecting:
      console.log("Connecting...");
      break;
    case ConnectionState.Connected:
      console.log("Connected!");
      break;
    case ConnectionState.Disconnected:
      console.log("Disconnected");
      break;
    case ConnectionState.Error:
      console.log("Connection error");
      break;
  }
});
```

### Error Handling

```typescript
client.onError((error) => {
  console.error("Client error:", error);
});

// Or use try/catch
try {
  await client.connect();
} catch (error) {
  if (error instanceof ConnectionError) {
    console.error("Failed to connect:", error.message);
  } else if (error instanceof AuthenticationError) {
    console.error("Authentication failed");
  }
}
```

## Configuration Options

```typescript
interface SensoctoConfig {
  // Required
  serverUrl: string;

  // Authentication
  bearerToken?: string;

  // Connector identification
  connectorName?: string; // default: "TypeScript Connector"
  connectorType?: string; // default: "typescript"
  connectorId?: string; // auto-generated if not provided

  // Connection behavior
  autoJoinConnector?: boolean; // default: true
  heartbeatIntervalMs?: number; // default: 30000
  connectionTimeoutMs?: number; // default: 10000
  autoReconnect?: boolean; // default: true
  maxReconnectAttempts?: number; // default: 5

  // Features
  features?: string[];
}
```

## Sensor Configuration

```typescript
interface SensorConfig {
  // Required
  sensorName: string;

  // Optional
  sensorId?: string; // auto-generated if not provided
  sensorType?: string; // default: "generic"
  attributes?: string[]; // list of attribute IDs
  samplingRateHz?: number; // default: 10
  batchSize?: number; // default: 5
}
```

## Error Types

The SDK provides specific error types for different failure scenarios:

- `SensoctoError` - Base error class
- `ConnectionError` - Connection failures
- `ChannelJoinError` - Failed to join a channel
- `AuthenticationError` - Authentication failures
- `TimeoutError` - Operation timeouts
- `InvalidConfigError` - Configuration validation errors
- `DisconnectedError` - Operation attempted while disconnected
- `InvalidAttributeIdError` - Invalid attribute ID format
- `ChannelError` - Channel operation failures

## Browser Support

- Chrome 80+
- Firefox 75+
- Safari 13.1+
- Edge 80+

## Node.js Support

- Node.js 18+
- Requires `ws` package for WebSocket support

```bash
npm install ws
```

## TypeScript

Full TypeScript support with strict typing. All types are exported from the main entry point:

```typescript
import type {
  SensoctoConfig,
  SensorConfig,
  Measurement,
  BackpressureConfig,
  CallParticipant,
  IceServer,
} from "@sensocto/threejs";
```

## License

MIT
