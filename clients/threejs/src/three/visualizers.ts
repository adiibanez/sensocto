/**
 * Sensor data visualization utilities for Three.js.
 * @module three/visualizers
 */

import type { ColorRepresentation, Object3D, Scene } from "three";
import { Color, Line, BufferGeometry, LineBasicMaterial, Vector3 } from "three";

import { AttentionLevel, type BackpressureConfig } from "../models.js";
import { type SensorStream } from "../sensor.js";

import { SensorObject3D } from "./SensorObject3D.js";

/**
 * Default colors for attention levels.
 */
export const AttentionLevelColors: Record<AttentionLevel, number> = {
  [AttentionLevel.None]: 0x00ff00, // Green - all good
  [AttentionLevel.Low]: 0xffff00, // Yellow - slight backpressure
  [AttentionLevel.Medium]: 0xffa500, // Orange - moderate backpressure
  [AttentionLevel.High]: 0xff0000, // Red - high backpressure
};

/**
 * Creates a material that responds to sensor backpressure.
 *
 * @param baseColor - The base color when there's no backpressure
 * @returns A material that can be updated with attention levels
 *
 * @example
 * ```typescript
 * const material = createSensorMaterial(0x0088ff);
 * const mesh = new THREE.Mesh(geometry, material);
 *
 * // Update when backpressure changes
 * sensor.onBackpressure((config) => {
 *   material.color.setHex(AttentionLevelColors[config.attentionLevel]);
 * });
 * ```
 */
export function createSensorMaterial(baseColor: ColorRepresentation = 0x00ff00): {
  color: Color;
  updateAttentionLevel: (level: AttentionLevel) => void;
} {
  const color = new Color(baseColor);

  return {
    color,
    updateAttentionLevel: (level: AttentionLevel): void => {
      color.setHex(AttentionLevelColors[level]);
    },
  };
}

/**
 * Function to map sensor values to object properties.
 */
export type ValueMapper = (
  value: Record<string, unknown> | number | number[],
  object: Object3D
) => void;

/**
 * Options for SensorDataVisualizer.
 */
export interface SensorDataVisualizerOptions {
  /** Maximum number of trail points to keep. */
  maxTrailPoints?: number;
  /** Whether to show trails by default. */
  showTrails?: boolean;
  /** Trail color. */
  trailColor?: ColorRepresentation;
  /** Trail opacity. */
  trailOpacity?: number;
}

/**
 * Manages visualization of sensor data streams in a Three.js scene.
 *
 * Provides automatic binding of sensor data to 3D objects,
 * trail visualization, and data history tracking.
 *
 * @example
 * ```typescript
 * import { SensorDataVisualizer } from "@sensocto/threejs/three";
 *
 * const scene = new THREE.Scene();
 * const visualizer = new SensorDataVisualizer(scene);
 *
 * // Create sensor objects
 * const sensorObject = new SensorObject3D();
 * scene.add(sensorObject);
 *
 * // Bind sensor to object with custom value mapping
 * visualizer.bindSensor(sensor, sensorObject, {
 *   position: (value, obj) => {
 *     const data = value as { x: number; y: number; z: number };
 *     obj.position.set(data.x, data.y, data.z);
 *   },
 * });
 *
 * // Enable trail for position tracking
 * visualizer.enableTrail(sensorObject);
 * ```
 */
export class SensorDataVisualizer {
  private readonly scene: Scene;
  private readonly options: Required<SensorDataVisualizerOptions>;
  private readonly bindings: Map<
    SensorStream,
    {
      object: SensorObject3D;
      valueMappers: Record<string, ValueMapper>;
      unsubscribe: () => void;
    }
  > = new Map();
  private readonly trails: Map<
    Object3D,
    {
      line: Line;
      points: Vector3[];
      geometry: BufferGeometry;
    }
  > = new Map();

  /**
   * Creates a new SensorDataVisualizer.
   *
   * @param scene - The Three.js scene
   * @param options - Configuration options
   */
  constructor(scene: Scene, options: SensorDataVisualizerOptions = {}) {
    this.scene = scene;
    this.options = {
      maxTrailPoints: options.maxTrailPoints ?? 100,
      showTrails: options.showTrails ?? false,
      trailColor: options.trailColor ?? 0x00ffff,
      trailOpacity: options.trailOpacity ?? 0.5,
    };
  }

  /**
   * Binds a sensor stream to a 3D object.
   *
   * @param sensor - The sensor stream
   * @param object - The SensorObject3D to update
   * @param valueMappers - Functions to map attribute values to object properties
   * @returns A function to unbind the sensor
   */
  bindSensor(
    sensor: SensorStream,
    object: SensorObject3D,
    valueMappers: Record<string, ValueMapper> = {}
  ): () => void {
    // Set up backpressure handler
    const unsubscribe = (): void => {
      sensor.onBackpressure(() => {
        // Remove the handler by setting a no-op
      });
    };

    sensor.onBackpressure((config: BackpressureConfig) => {
      object.setAttentionLevel(config.attentionLevel);

      // Pulse on high backpressure
      if (config.attentionLevel === AttentionLevel.High) {
        object.pulse(100, 1.1);
      }
    });

    this.bindings.set(sensor, { object, valueMappers, unsubscribe });

    // Return unbind function
    return () => {
      this.unbindSensor(sensor);
    };
  }

  /**
   * Unbinds a sensor from its object.
   *
   * @param sensor - The sensor stream to unbind
   */
  unbindSensor(sensor: SensorStream): void {
    const binding = this.bindings.get(sensor);
    if (binding) {
      binding.unsubscribe();
      this.bindings.delete(sensor);
    }
  }

  /**
   * Updates a bound object with new measurement data.
   *
   * @param sensor - The sensor that received data
   * @param attributeId - The attribute ID
   * @param value - The measurement value
   */
  updateFromMeasurement(
    sensor: SensorStream,
    attributeId: string,
    value: Record<string, unknown> | number | number[]
  ): void {
    const binding = this.bindings.get(sensor);
    if (!binding) {
      return;
    }

    const mapper = binding.valueMappers[attributeId];
    if (mapper) {
      mapper(value, binding.object);
    }

    // Update trail if enabled
    const trail = this.trails.get(binding.object);
    if (trail) {
      this.updateTrail(binding.object);
    }

    // Pulse on data update
    binding.object.pulse(50, 1.05);
  }

  /**
   * Enables position trail visualization for an object.
   *
   * @param object - The object to track
   * @returns The trail line object
   */
  enableTrail(object: Object3D): Line {
    // Check if trail already exists
    const existing = this.trails.get(object);
    if (existing) {
      return existing.line;
    }

    const points: Vector3[] = [];
    const geometry = new BufferGeometry();
    const material = new LineBasicMaterial({
      color: this.options.trailColor,
      transparent: true,
      opacity: this.options.trailOpacity,
    });

    const line = new Line(geometry, material);
    this.scene.add(line);

    this.trails.set(object, { line, points, geometry });

    return line;
  }

  /**
   * Disables trail visualization for an object.
   *
   * @param object - The object to stop tracking
   */
  disableTrail(object: Object3D): void {
    const trail = this.trails.get(object);
    if (trail) {
      this.scene.remove(trail.line);
      trail.geometry.dispose();
      (trail.line.material as LineBasicMaterial).dispose();
      this.trails.delete(object);
    }
  }

  /**
   * Clears the trail for an object.
   *
   * @param object - The object whose trail to clear
   */
  clearTrail(object: Object3D): void {
    const trail = this.trails.get(object);
    if (trail) {
      trail.points.length = 0;
      trail.geometry.setFromPoints([]);
    }
  }

  /**
   * Updates all trails (call this in your animation loop).
   */
  updateAllTrails(): void {
    for (const [object] of this.trails) {
      this.updateTrail(object);
    }
  }

  /**
   * Gets all bound sensors.
   */
  getBoundSensors(): SensorStream[] {
    return Array.from(this.bindings.keys());
  }

  /**
   * Gets the object bound to a sensor.
   */
  getObjectForSensor(sensor: SensorStream): SensorObject3D | undefined {
    return this.bindings.get(sensor)?.object;
  }

  /**
   * Disposes of all resources.
   */
  dispose(): void {
    // Unbind all sensors
    for (const sensor of this.bindings.keys()) {
      this.unbindSensor(sensor);
    }

    // Dispose all trails
    for (const [object] of this.trails) {
      this.disableTrail(object);
    }
  }

  private updateTrail(object: Object3D): void {
    const trail = this.trails.get(object);
    if (!trail) {
      return;
    }

    // Add current position
    trail.points.push(object.position.clone());

    // Limit trail length
    while (trail.points.length > this.options.maxTrailPoints) {
      trail.points.shift();
    }

    // Update geometry
    trail.geometry.setFromPoints(trail.points);
  }
}
