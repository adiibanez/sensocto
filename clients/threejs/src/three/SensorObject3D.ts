/**
 * Three.js Object3D wrapper for sensor visualization.
 * @module three/SensorObject3D
 */

import type {
  BufferGeometry,
  ColorRepresentation,
  Material,
  NormalBufferAttributes,
  Object3DEventMap,
} from "three";
import { Color, Group, Mesh, MeshStandardMaterial, SphereGeometry } from "three";

import { AttentionLevel } from "../models.js";

/**
 * Options for creating a SensorObject3D.
 */
export interface SensorObject3DOptions {
  /** Custom geometry for the sensor representation. */
  geometry?: BufferGeometry<NormalBufferAttributes>;
  /** Custom material for the sensor. */
  material?: Material;
  /** Initial color of the sensor. */
  color?: ColorRepresentation;
  /** Whether to show attention level through color changes. */
  showAttentionLevel?: boolean;
  /** Custom colors for attention levels. */
  attentionColors?: Partial<Record<AttentionLevel, ColorRepresentation>>;
}

/**
 * Default colors for attention levels.
 */
const DEFAULT_ATTENTION_COLORS: Record<AttentionLevel, ColorRepresentation> = {
  [AttentionLevel.None]: 0x00ff00, // Green
  [AttentionLevel.Low]: 0xffff00, // Yellow
  [AttentionLevel.Medium]: 0xffa500, // Orange
  [AttentionLevel.High]: 0xff0000, // Red
};

/**
 * A Three.js Group that represents a sensor in 3D space.
 *
 * Provides easy binding of sensor data to 3D visualization, including:
 * - Position updates from sensor measurements
 * - Color changes based on backpressure/attention levels
 * - Scaling based on sensor values
 *
 * @example
 * ```typescript
 * import { SensorObject3D } from "@sensocto/threejs/three";
 * import * as THREE from "three";
 *
 * const scene = new THREE.Scene();
 *
 * // Create with default sphere geometry
 * const sensor = new SensorObject3D();
 * scene.add(sensor);
 *
 * // Or with custom geometry
 * const customSensor = new SensorObject3D({
 *   geometry: new THREE.BoxGeometry(1, 1, 1),
 *   color: 0x0088ff,
 * });
 * scene.add(customSensor);
 *
 * // Update from sensor data
 * sensor.setPosition(x, y, z);
 * sensor.setAttentionLevel(AttentionLevel.Medium);
 * sensor.setValue(0.75); // Affects scale/opacity
 * ```
 */
export class SensorObject3D extends Group<Object3DEventMap> {
  private readonly mesh: Mesh;
  private readonly baseMaterial: MeshStandardMaterial;
  private readonly showAttentionLevel: boolean;
  private readonly attentionColors: Record<AttentionLevel, Color>;
  private currentAttentionLevel: AttentionLevel = AttentionLevel.None;
  private currentValue = 1;
  private baseScale = 1;

  /**
   * Creates a new SensorObject3D.
   *
   * @param options - Configuration options
   */
  constructor(options: SensorObject3DOptions = {}) {
    super();

    const geometry = options.geometry ?? new SphereGeometry(0.5, 32, 32);
    const color = options.color ?? 0x00ff00;
    this.showAttentionLevel = options.showAttentionLevel ?? true;

    // Create material
    if (options.material) {
      this.baseMaterial = options.material as MeshStandardMaterial;
    } else {
      this.baseMaterial = new MeshStandardMaterial({
        color,
        metalness: 0.3,
        roughness: 0.7,
        transparent: true,
        opacity: 1,
      });
    }

    // Set up attention colors
    this.attentionColors = {
      [AttentionLevel.None]: new Color(
        options.attentionColors?.[AttentionLevel.None] ??
          DEFAULT_ATTENTION_COLORS[AttentionLevel.None]
      ),
      [AttentionLevel.Low]: new Color(
        options.attentionColors?.[AttentionLevel.Low] ??
          DEFAULT_ATTENTION_COLORS[AttentionLevel.Low]
      ),
      [AttentionLevel.Medium]: new Color(
        options.attentionColors?.[AttentionLevel.Medium] ??
          DEFAULT_ATTENTION_COLORS[AttentionLevel.Medium]
      ),
      [AttentionLevel.High]: new Color(
        options.attentionColors?.[AttentionLevel.High] ??
          DEFAULT_ATTENTION_COLORS[AttentionLevel.High]
      ),
    };

    // Create mesh
    this.mesh = new Mesh(geometry, this.baseMaterial);
    this.add(this.mesh);
  }

  /**
   * Gets the internal mesh.
   */
  getMesh(): Mesh {
    return this.mesh;
  }

  /**
   * Gets the internal material.
   */
  getMaterial(): MeshStandardMaterial {
    return this.baseMaterial;
  }

  /**
   * Sets the position from sensor data.
   *
   * @param x - X coordinate
   * @param y - Y coordinate
   * @param z - Z coordinate
   */
  setPosition(x: number, y: number, z: number): void {
    this.position.set(x, y, z);
  }

  /**
   * Sets the position from a position payload.
   *
   * @param payload - Object containing x, y, z coordinates
   */
  setPositionFromPayload(payload: { x?: number; y?: number; z?: number }): void {
    this.position.set(payload.x ?? 0, payload.y ?? 0, payload.z ?? 0);
  }

  /**
   * Sets the rotation from sensor data (in radians).
   *
   * @param x - X rotation
   * @param y - Y rotation
   * @param z - Z rotation
   */
  setRotation(x: number, y: number, z: number): void {
    this.rotation.set(x, y, z);
  }

  /**
   * Sets the rotation from a rotation payload.
   *
   * @param payload - Object containing x, y, z rotations
   */
  setRotationFromPayload(payload: { x?: number; y?: number; z?: number }): void {
    this.rotation.set(payload.x ?? 0, payload.y ?? 0, payload.z ?? 0);
  }

  /**
   * Sets the attention level (affects color when showAttentionLevel is true).
   *
   * @param level - The attention level
   */
  setAttentionLevel(level: AttentionLevel): void {
    this.currentAttentionLevel = level;

    if (this.showAttentionLevel) {
      const color = this.attentionColors[level];
      this.baseMaterial.color.copy(color);
    }
  }

  /**
   * Gets the current attention level.
   */
  getAttentionLevel(): AttentionLevel {
    return this.currentAttentionLevel;
  }

  /**
   * Sets a normalized value (0-1) that affects the sensor appearance.
   *
   * This can be used to represent sensor intensity, signal strength, etc.
   *
   * @param value - Normalized value between 0 and 1
   * @param affectScale - Whether to affect scale (default: true)
   * @param affectOpacity - Whether to affect opacity (default: false)
   */
  setValue(value: number, affectScale = true, affectOpacity = false): void {
    this.currentValue = Math.max(0, Math.min(1, value));

    if (affectScale) {
      const scaleFactor = 0.5 + this.currentValue * 0.5; // Scale between 0.5 and 1
      this.scale.setScalar(this.baseScale * scaleFactor);
    }

    if (affectOpacity) {
      this.baseMaterial.opacity = 0.3 + this.currentValue * 0.7; // Opacity between 0.3 and 1
    }
  }

  /**
   * Gets the current value.
   */
  getValue(): number {
    return this.currentValue;
  }

  /**
   * Sets the base scale of the sensor object.
   *
   * @param scale - The base scale factor
   */
  setBaseScale(scale: number): void {
    this.baseScale = scale;
    this.scale.setScalar(scale);
  }

  /**
   * Sets the color directly (overrides attention level colors).
   *
   * @param color - The color to set
   */
  setColor(color: ColorRepresentation): void {
    this.baseMaterial.color.set(color);
  }

  /**
   * Enables or disables the sensor visualization.
   *
   * @param enabled - Whether the sensor is enabled
   */
  setEnabled(enabled: boolean): void {
    this.visible = enabled;
    this.baseMaterial.opacity = enabled ? 1 : 0.3;
  }

  /**
   * Pulses the sensor (for visual feedback on data updates).
   *
   * @param duration - Duration of the pulse in milliseconds
   * @param intensity - Intensity of the pulse (scale multiplier)
   */
  pulse(duration = 200, intensity = 1.2): void {
    const originalScale = this.scale.x;
    this.scale.setScalar(originalScale * intensity);

    setTimeout(() => {
      this.scale.setScalar(originalScale);
    }, duration);
  }

  /**
   * Disposes of all resources.
   */
  dispose(): void {
    this.mesh.geometry.dispose();
    this.baseMaterial.dispose();
  }
}
