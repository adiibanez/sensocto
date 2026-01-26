/**
 * Three.js integration for Sensocto.
 *
 * This module provides utilities for visualizing sensor data in Three.js scenes.
 * Requires Three.js as a peer dependency.
 *
 * @packageDocumentation
 *
 * @example
 * ```typescript
 * import { SensoctoClient } from "@sensocto/threejs";
 * import {
 *   SensorObject3D,
 *   createSensorMaterial,
 *   SensorDataVisualizer,
 * } from "@sensocto/threejs/three";
 * import * as THREE from "three";
 *
 * // Create scene
 * const scene = new THREE.Scene();
 *
 * // Create sensor visualization
 * const sensorObject = new SensorObject3D({
 *   geometry: new THREE.SphereGeometry(0.5, 32, 32),
 * });
 * scene.add(sensorObject);
 *
 * // Create visualizer for data streams
 * const visualizer = new SensorDataVisualizer(scene);
 *
 * // Connect to sensor
 * const client = new SensoctoClient({ serverUrl: "..." });
 * await client.connect();
 *
 * const sensor = await client.registerSensor({
 *   sensorName: "Position Tracker",
 *   attributes: ["position"],
 * });
 *
 * // Update visualization when data arrives
 * visualizer.bindSensor(sensor, sensorObject);
 * ```
 *
 * @module @sensocto/threejs/three
 */

export { SensorObject3D } from "./SensorObject3D.js";
export type { SensorObject3DOptions } from "./SensorObject3D.js";

export { AttentionLevelColors, createSensorMaterial, SensorDataVisualizer } from "./visualizers.js";
export type { SensorDataVisualizerOptions, ValueMapper } from "./visualizers.js";
