import * as THREE from 'three';

// GPU-accelerated wind particle system.
// Renders thousands of soft-glow particles advected along a wind field.
// Uses custom ShaderMaterial with additive blending for ethereal effect.
// Supports three spawn modes: ambient drift, canopy (falling), geyser (ballistic eruptions).

const VERT = `
  attribute float aSize;
  attribute float aAlpha;
  attribute vec3 aColor;

  varying float vAlpha;
  varying vec3 vColor;

  void main() {
    vAlpha = aAlpha;
    vColor = aColor;
    vec4 mvPos = modelViewMatrix * vec4(position, 1.0);
    gl_PointSize = aSize * (600.0 / -mvPos.z);
    gl_PointSize = clamp(gl_PointSize, 1.0, 160.0);
    gl_Position = projectionMatrix * mvPos;
  }
`;

const FRAG = `
  varying float vAlpha;
  varying vec3 vColor;

  void main() {
    float d = length(gl_PointCoord - vec2(0.5));
    if (d > 0.5) discard;
    float glow = exp(-d * d * 10.0);
    float core = exp(-d * d * 40.0) * 0.5;
    gl_FragColor = vec4(vColor * (glow + core), vAlpha * glow);
  }
`;

// Gaussian random (Box-Muller) for natural spread
function randn() {
  return Math.sqrt(-2 * Math.log(1 - Math.random())) * Math.cos(2 * Math.PI * Math.random());
}

// Per-world particle configurations
export const PARTICLE_CONFIGS = {
  bioluminescent: {
    count: 8000,
    colors: [[0.4, 0.85, 1.0], [0.6, 0.3, 1.0], [0.2, 0.95, 0.5], [0.7, 0.5, 1.0]],
    sizeRange: [0.048, 0.15],
    opacityRange: [0.25, 0.7],
    bounds: { x: 14, y: 5, z: 14 },
    maxLife: 14,
    speed: 0.8,
    upBias: -0.45,
    // Heights match canopy base (3.2 * hScale) from treeVariations in avatar_splat_hook.js
    sources: [
      { x: -2.5, z: -1.5, height: 3.2 },   // tree 0: hScale 1.0  → 3.2 * 1.0  = 3.2
      { x:  1.8, z: -2.0, height: 4.0 },   // tree 1: hScale 1.25 → 3.2 * 1.25 = 4.0
      { x: -0.5, z:  2.5, height: 2.24 },  // tree 2: hScale 0.7  → 3.2 * 0.7  = 2.24
      { x:  3.0, z:  1.0, height: 4.48 },  // tree 3: hScale 1.4  → 3.2 * 1.4  = 4.48
      { x: -3.5, z:  0.5, height: 2.72 },  // tree 4: hScale 0.85 → 3.2 * 0.85 = 2.72
    ],
    sourceRatio: 0.8,
    sourceSpread: 0.7,
    sourceSpawnMode: 'canopy',
  },
  inferno: {
    count: 10000,
    colors: [[1.0, 0.45, 0.0], [1.0, 0.2, 0.0], [1.0, 0.65, 0.1], [1.0, 0.8, 0.2]],
    sizeRange: [0.08, 0.35],
    opacityRange: [0.5, 1.0],
    bounds: { x: 14, y: 12, z: 14 },
    maxLife: 6,
    speed: 1.5,
    upBias: 0.3,
    sources: [
      { x: -2.0, z: -1.5, power: 1.2 },
      { x:  1.5, z: -2.0, power: 1.0 },
      { x:  0.0, z:  2.0, power: 1.4 },
      { x:  2.5, z:  0.5, power: 0.9 },
      { x: -3.0, z:  1.0, power: 1.1 },
    ],
    sourceRatio: 0.9,
    sourceSpread: 0.3,
    sourceSpawnMode: 'geyser',
    // Geyser parameters
    gravity: 4.5,           // m/s² downward (lower than real for drama)
    eruptVelMin: 4.0,       // min upward launch speed
    eruptVelMax: 9.0,       // max upward launch speed
    eruptSpreadVel: 1.5,    // horizontal velocity spread
    eruptInterval: 2.5,     // seconds between eruption bursts per source
    eruptDuration: 0.8,     // how long each burst lasts
    eruptJitter: 1.5,       // random offset per source so they don't sync
  },
  meadow: {
    count: 6000,
    colors: [[1.0, 0.92, 0.4], [0.9, 0.82, 0.35], [1.0, 1.0, 0.7], [0.85, 0.75, 0.3]],
    sizeRange: [0.06, 0.2],
    opacityRange: [0.2, 0.55],
    bounds: { x: 14, y: 4, z: 14 },
    maxLife: 12,
    speed: 1.2,
    upBias: 0.08,
  },
};

export class WindParticles {
  constructor(threeScene, worldKey) {
    const config = PARTICLE_CONFIGS[worldKey] || PARTICLE_CONFIGS.bioluminescent;
    this.config = config;
    this.count = config.count;

    // Per-particle arrays
    this.pos = new Float32Array(this.count * 3);
    this.vel = new Float32Array(this.count * 3); // velocity (used in geyser mode)
    this.baseAlphas = new Float32Array(this.count);
    this.alphas = new Float32Array(this.count);
    this.sizes = new Float32Array(this.count);
    this.colors = new Float32Array(this.count * 3);
    this.lives = new Float32Array(this.count);
    this.ages = new Float32Array(this.count);

    // Per-source eruption phase offsets (stagger geysers)
    if (config.sources && config.sourceSpawnMode === 'geyser') {
      this._eruptPhases = config.sources.map(() =>
        Math.random() * (config.eruptJitter || 2.0)
      );
    }

    for (let i = 0; i < this.count; i++) this._spawn(i, true);

    this.geometry = new THREE.BufferGeometry();
    this.geometry.setAttribute('position', new THREE.BufferAttribute(this.pos, 3));
    this.geometry.setAttribute('aSize', new THREE.BufferAttribute(this.sizes, 1));
    this.geometry.setAttribute('aAlpha', new THREE.BufferAttribute(this.alphas, 1));
    this.geometry.setAttribute('aColor', new THREE.BufferAttribute(this.colors, 3));

    this.material = new THREE.ShaderMaterial({
      vertexShader: VERT,
      fragmentShader: FRAG,
      transparent: true,
      blending: THREE.AdditiveBlending,
      depthTest: false,
      depthWrite: false,
    });

    this.points = new THREE.Points(this.geometry, this.material);
    threeScene.add(this.points);
  }

  // Check if a specific geyser source is currently erupting
  _isErupting(sourceIdx, time) {
    const cfg = this.config;
    const interval = cfg.eruptInterval || 2.5;
    const duration = cfg.eruptDuration || 0.8;
    const phase = this._eruptPhases ? this._eruptPhases[sourceIdx] : 0;
    const t = (time + phase) % interval;
    return t < duration;
  }

  _spawn(i, randomAge) {
    const i3 = i * 3;
    const cfg = this.config;
    const b = cfg.bounds;
    const sources = cfg.sources;
    const fromSource = sources && Math.random() < (cfg.sourceRatio || 0);

    // Reset velocity
    this.vel[i3] = 0;
    this.vel[i3 + 1] = 0;
    this.vel[i3 + 2] = 0;

    if (fromSource) {
      const srcIdx = Math.floor(Math.random() * sources.length);
      const src = sources[srcIdx];
      const spread = cfg.sourceSpread || 0.3;

      if (cfg.sourceSpawnMode === 'canopy') {
        // Canopy mode: spawn scattered around tree crown, drift down
        const spawnH = (src.height || 3.0) + randn() * 0.4;
        this.pos[i3]     = src.x + randn() * spread * 0.5;
        this.pos[i3 + 1] = spawnH;
        this.pos[i3 + 2] = src.z + randn() * spread * 0.5;

        const palette = cfg.colors;
        const c = palette[Math.floor(Math.random() * palette.length)];
        this.colors[i3]     = c[0] + (Math.random() - 0.5) * 0.1;
        this.colors[i3 + 1] = c[1] + (Math.random() - 0.5) * 0.1;
        this.colors[i3 + 2] = c[2] + (Math.random() - 0.5) * 0.1;

        const [sMin, sMax] = cfg.sizeRange;
        this.sizes[i] = sMin + Math.random() * (sMax - sMin);
        const [oMin, oMax] = cfg.opacityRange;
        this.baseAlphas[i] = oMin + Math.random() * (oMax - oMin);
        this.lives[i] = 4 + Math.random() * 8;

      } else if (cfg.sourceSpawnMode === 'geyser') {
        // Geyser mode: ballistic eruption from source
        const power = src.power || 1.0;
        this.pos[i3]     = src.x + randn() * spread * 0.4;
        this.pos[i3 + 1] = Math.abs(randn() * 0.15);
        this.pos[i3 + 2] = src.z + randn() * spread * 0.4;

        // Launch velocity — strong upward + some horizontal scatter
        const velMin = cfg.eruptVelMin || 4.0;
        const velMax = cfg.eruptVelMax || 9.0;
        const spreadVel = cfg.eruptSpreadVel || 1.5;
        this.vel[i3]     = randn() * spreadVel * power;
        this.vel[i3 + 1] = (velMin + Math.random() * (velMax - velMin)) * power;
        this.vel[i3 + 2] = randn() * spreadVel * power;

        // Lava blob color: bright white-yellow at spawn
        const t = Math.random();
        if (t < 0.3) {
          // White-hot core
          this.colors[i3] = 1.0; this.colors[i3+1] = 0.95; this.colors[i3+2] = 0.7 + Math.random() * 0.3;
        } else if (t < 0.65) {
          // Bright yellow-orange
          this.colors[i3] = 1.0; this.colors[i3+1] = 0.7 + Math.random() * 0.2; this.colors[i3+2] = 0.1 + Math.random() * 0.15;
        } else {
          // Orange
          this.colors[i3] = 1.0; this.colors[i3+1] = 0.4 + Math.random() * 0.2; this.colors[i3+2] = Math.random() * 0.05;
        }

        // Lava blobs: bigger, shorter life
        const [sMin, sMax] = cfg.sizeRange;
        this.sizes[i] = sMin + Math.random() * (sMax - sMin);
        this.baseAlphas[i] = 0.6 + Math.random() * 0.4;
        this.lives[i] = 2.0 + Math.random() * 4.0;

      } else {
        // Legacy fire mode (unused now but kept for safety)
        const spawnH = Math.abs(randn() * 0.2);
        this.pos[i3]     = src.x + randn() * spread * 0.5;
        this.pos[i3 + 1] = spawnH;
        this.pos[i3 + 2] = src.z + randn() * spread * 0.5;

        const t = Math.random();
        if (t < 0.25) {
          this.colors[i3] = 1.0; this.colors[i3+1] = 0.9+Math.random()*0.1; this.colors[i3+2] = 0.6+Math.random()*0.3;
        } else if (t < 0.6) {
          this.colors[i3] = 1.0; this.colors[i3+1] = 0.5+Math.random()*0.3; this.colors[i3+2] = Math.random()*0.1;
        } else {
          this.colors[i3] = 1.0; this.colors[i3+1] = 0.15+Math.random()*0.25; this.colors[i3+2] = 0.0;
        }

        const [sMin, sMax] = cfg.sizeRange;
        this.sizes[i] = sMin + Math.random() * (sMax - sMin) * 0.7;
        this.baseAlphas[i] = 0.5 + Math.random() * 0.45;
        this.lives[i] = 1.5 + Math.random() * 3.0;
      }
    } else {
      // Ambient particles: scattered across bounds
      this.pos[i3]     = (Math.random() - 0.5) * b.x;
      this.pos[i3 + 1] = Math.random() * b.y;
      this.pos[i3 + 2] = (Math.random() - 0.5) * b.z;

      const palette = cfg.colors;
      const c = palette[Math.floor(Math.random() * palette.length)];
      this.colors[i3]     = c[0] + (Math.random() - 0.5) * 0.1;
      this.colors[i3 + 1] = c[1] + (Math.random() - 0.5) * 0.1;
      this.colors[i3 + 2] = c[2] + (Math.random() - 0.5) * 0.1;

      const [sMin, sMax] = cfg.sizeRange;
      this.sizes[i] = sMin + Math.random() * (sMax - sMin);
      const [oMin, oMax] = cfg.opacityRange;
      this.baseAlphas[i] = oMin + Math.random() * (oMax - oMin);
      const ml = cfg.maxLife;
      this.lives[i] = 2 + Math.random() * (ml - 2);
    }

    this.alphas[i] = 0;
    this.ages[i] = randomAge ? Math.random() * this.lives[i] : 0;
  }

  // Geyser respawn: only launch if source is currently erupting
  _spawnGeyser(i, time) {
    const cfg = this.config;
    const sources = cfg.sources;

    // Pick a random source and check if it's erupting
    const srcIdx = Math.floor(Math.random() * sources.length);
    if (this._isErupting(srcIdx, time)) {
      // Full geyser spawn
      this._spawn(i, false);
    } else {
      // Not erupting: spawn as small ambient ember instead
      const i3 = i * 3;
      const b = cfg.bounds;
      this.vel[i3] = 0; this.vel[i3+1] = 0; this.vel[i3+2] = 0;

      // Spawn near a random source at ground level (smoldering)
      const src = sources[Math.floor(Math.random() * sources.length)];
      this.pos[i3]     = src.x + randn() * 0.5;
      this.pos[i3 + 1] = Math.abs(randn() * 0.1);
      this.pos[i3 + 2] = src.z + randn() * 0.5;

      // Dim ember color
      this.colors[i3] = 0.8 + Math.random() * 0.2;
      this.colors[i3+1] = 0.15 + Math.random() * 0.15;
      this.colors[i3+2] = 0;

      const [sMin] = cfg.sizeRange;
      this.sizes[i] = sMin * (0.3 + Math.random() * 0.4);
      this.baseAlphas[i] = 0.2 + Math.random() * 0.3;
      this.lives[i] = 1.0 + Math.random() * 2.0;
      this.alphas[i] = 0;
      this.ages[i] = 0;
    }
  }

  update(dt, time, windIntensity, windField, dataPulse) {
    const cfg = this.config;
    const b = cfg.bounds;
    const speed = cfg.speed;
    const upBias = cfg.upBias;
    const pulseBoost = 1 + dataPulse * 2;
    const isGeyser = cfg.sourceSpawnMode === 'geyser';
    const gravity = cfg.gravity || 0;

    for (let i = 0; i < this.count; i++) {
      const i3 = i * 3;
      this.ages[i] += dt;

      if (this.ages[i] >= this.lives[i] ||
          Math.abs(this.pos[i3]) > b.x * 0.55 ||
          this.pos[i3 + 1] > b.y * 1.1 || this.pos[i3 + 1] < -0.5 ||
          Math.abs(this.pos[i3 + 2]) > b.z * 0.55) {
        if (isGeyser) {
          this._spawnGeyser(i, time);
        } else {
          this._spawn(i, false);
        }
        continue;
      }

      if (isGeyser) {
        // Ballistic trajectory: velocity + gravity + light wind influence
        this.vel[i3 + 1] -= gravity * dt; // gravity pulls down

        // Light wind drift (weaker than pure wind mode)
        const v = windField.flow(this.pos[i3], this.pos[i3 + 1], this.pos[i3 + 2], time);
        const ws = windIntensity * speed * 0.3 * dt;
        this.vel[i3]     += v.x * ws;
        this.vel[i3 + 2] += v.z * ws;

        // Apply velocity
        this.pos[i3]     += this.vel[i3] * dt;
        this.pos[i3 + 1] += this.vel[i3 + 1] * dt;
        this.pos[i3 + 2] += this.vel[i3 + 2] * dt;

        // Bounce off ground (lava splatter)
        if (this.pos[i3 + 1] < 0.02 && this.vel[i3 + 1] < 0) {
          this.pos[i3 + 1] = 0.02;
          this.vel[i3 + 1] *= -0.25; // weak bounce (energy loss)
          this.vel[i3]     *= 0.5;
          this.vel[i3 + 2] *= 0.5;
          // Darken on impact — cooling lava
          this.colors[i3]     *= 0.85;
          this.colors[i3 + 1] *= 0.6;
        }
      } else {
        // Standard wind-advected motion
        const v = windField.flow(this.pos[i3], this.pos[i3 + 1], this.pos[i3 + 2], time);
        const s = windIntensity * speed * pulseBoost * dt;
        this.pos[i3]     += v.x * s;
        this.pos[i3 + 1] += v.y * s + upBias * windIntensity * dt;
        this.pos[i3 + 2] += v.z * s;
      }

      // Fade envelope
      const life = this.lives[i];
      const age = this.ages[i];
      const fadeIn = Math.min(1, age / 0.3);
      const fadeOut = age > life - 1.0 ? Math.max(0, (life - age) / 1.0) : 1;
      this.alphas[i] = this.baseAlphas[i] * fadeIn * fadeOut * Math.max(0.05, windIntensity) * pulseBoost;

      // Geyser: color cools with age, size grows slightly as blob stretches
      if (isGeyser) {
        const ageRatio = age / life;
        // Cool from spawn color toward dark red
        const cool = Math.min(1, ageRatio * 1.5);
        this.colors[i3]     = Math.max(0.3, this.colors[i3] - cool * 0.3);
        this.colors[i3 + 1] = Math.max(0.02, this.colors[i3 + 1] - cool * 0.4);
        this.colors[i3 + 2] = Math.max(0, this.colors[i3 + 2] - cool * 0.3);

        // Lava blobs expand slightly as they cool
        const [sMin, sMax] = cfg.sizeRange;
        const baseSize = sMin + (sMax - sMin) * 0.4;
        this.sizes[i] = baseSize * (1.0 + ageRatio * 0.8);
      }
    }

    this.geometry.attributes.position.needsUpdate = true;
    this.geometry.attributes.aAlpha.needsUpdate = true;
    if (isGeyser) {
      this.geometry.attributes.aColor.needsUpdate = true;
      this.geometry.attributes.aSize.needsUpdate = true;
    }
  }

  dispose() {
    if (this.points.parent) this.points.parent.remove(this.points);
    this.geometry.dispose();
    this.material.dispose();
  }
}
