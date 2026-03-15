import * as GaussianSplats3D from '@mkkellogg/gaussian-splats-3d';
import * as THREE from 'three';
import { WindField } from './wind_field.js';
import { WindParticles } from './wind_particles.js';

// Multi-world sensor-driven Gaussian Splat ecosystem with curl-noise wind simulation.
// Each world generates procedural geometry, lights, and wind-driven particle effects.

// --- Shared utilities ---

function randn() {
  const u = 1 - Math.random();
  const v = Math.random();
  return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
}
function lerp(a, b, t) { return a + (b - a) * t; }
function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }

function hslToRgb(h, s, l) {
  let r, g, b;
  if (s === 0) { r = g = b = l; }
  else {
    const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
    const p = 2 * l - q;
    const hue2rgb = (p, q, t) => {
      if (t < 0) t += 1; if (t > 1) t -= 1;
      if (t < 1/6) return p + (q - p) * 6 * t;
      if (t < 1/2) return q;
      if (t < 2/3) return p + (q - p) * (2/3 - t) * 6;
      return p;
    };
    r = hue2rgb(p, q, h + 1/3);
    g = hue2rgb(p, q, h);
    b = hue2rgb(p, q, h - 1/3);
  }
  return [Math.round(r * 255), Math.round(g * 255), Math.round(b * 255)];
}

function makeSplat(x, y, z, sx, sy, sz, r, g, b, a) {
  return {
    x, y, z,
    sx: Math.max(0.005, sx), sy: Math.max(0.005, sy), sz: Math.max(0.005, sz),
    r: clamp(Math.round(r), 0, 255), g: clamp(Math.round(g), 0, 255),
    b: clamp(Math.round(b), 0, 255), a: clamp(Math.round(a), 1, 254)
  };
}

function addCluster(arr, cx, cy, cz, spreadX, spreadY, spreadZ, color, count, scale, opacity) {
  for (let i = 0; i < count; i++) {
    const sc = scale * (0.6 + Math.random() * 0.8);
    arr.push(makeSplat(
      cx + randn() * spreadX, cy + Math.abs(randn() * spreadY), cz + randn() * spreadZ,
      sc, sc * 0.8, sc,
      color[0] + randn() * 15, color[1] + randn() * 15, color[2] + randn() * 15, opacity
    ));
  }
}

// --- PLY encoder ---

function splatsToPlyBlob(splats) {
  const header = [
    'ply', 'format binary_little_endian 1.0', `element vertex ${splats.length}`,
    'property float x', 'property float y', 'property float z',
    'property float nx', 'property float ny', 'property float nz',
    'property float f_dc_0', 'property float f_dc_1', 'property float f_dc_2',
    'property float opacity',
    'property float scale_0', 'property float scale_1', 'property float scale_2',
    'property float rot_0', 'property float rot_1', 'property float rot_2', 'property float rot_3',
    'end_header\n'
  ].join('\n');

  const headerBytes = new TextEncoder().encode(header);
  const bpv = 17 * 4;
  const buf = new ArrayBuffer(headerBytes.length + splats.length * bpv);
  new Uint8Array(buf).set(headerBytes);
  const dv = new DataView(buf);
  let off = headerBytes.length;
  const C = 0.28209479177387814;

  for (const s of splats) {
    dv.setFloat32(off, s.x, true); off += 4;
    dv.setFloat32(off, s.y, true); off += 4;
    dv.setFloat32(off, s.z, true); off += 4;
    dv.setFloat32(off, 0, true); off += 4;
    dv.setFloat32(off, 0, true); off += 4;
    dv.setFloat32(off, 0, true); off += 4;
    dv.setFloat32(off, (s.r / 255 - 0.5) / C, true); off += 4;
    dv.setFloat32(off, (s.g / 255 - 0.5) / C, true); off += 4;
    dv.setFloat32(off, (s.b / 255 - 0.5) / C, true); off += 4;
    const a = clamp(s.a / 255, 0.01, 0.99);
    dv.setFloat32(off, Math.log(a / (1 - a)), true); off += 4;
    dv.setFloat32(off, Math.log(s.sx), true); off += 4;
    dv.setFloat32(off, Math.log(s.sy), true); off += 4;
    dv.setFloat32(off, Math.log(s.sz), true); off += 4;
    dv.setFloat32(off, 1, true); off += 4;
    dv.setFloat32(off, 0, true); off += 4;
    dv.setFloat32(off, 0, true); off += 4;
    dv.setFloat32(off, 0, true); off += 4;
  }
  return new Blob([buf], { type: 'application/octet-stream' });
}

// ============================================================================
// WORLD: Bioluminescent (Avatar/Pandora ecosystem)
// ============================================================================

const BIO_PALETTE = {
  GROUND:   { base: [15, 40, 25],    glow: [30, 180, 80]   },
  TREE:     { base: [20, 60, 40],    glow: [40, 200, 120]  },
  CANOPY:   { base: [25, 80, 50],    glow: [60, 220, 140]  },
  MUSHROOM: { base: [80, 20, 120],   glow: [180, 60, 255]  },
  VINE:     { base: [30, 90, 60],    glow: [50, 200, 100]  },
  SPORE:    { base: [100, 180, 200], glow: [160, 240, 255] },
};

const BIO_TREE_POS  = [[-2.5, 0, -1.5], [1.8, 0, -2.0], [-0.5, 0, 2.5], [3.0, 0, 1.0], [-3.5, 0, 0.5]];
const BIO_MUSHROOM_POS = [[-1.0, 0, 0.5], [0.8, 0, -0.5], [-2.0, 0, 2.0], [2.5, 0, -1.0],
                          [0.0, 0, -2.5], [-3.0, 0, -1.0], [1.5, 0, 2.5]];
const BIO_FLOWER_POS = [[-1.5, 0, 1.5], [0.5, 0, 0.8], [2.0, 0, 0.0], [-0.5, 0, -1.5],
                        [1.0, 0, -2.5], [-2.5, 0, -2.0], [3.5, 0, -0.5], [-1.0, 0, -3.0]];

// Scene sample points for curl noise (conceptual center of each scene group)
const BIO_SAMPLE_PTS = [
  { x: 0, y: 0, z: 0 },       // 0: ground (static)
  { x: 0, y: 2.5, z: 0 },     // 1: trees (high, swaying)
  { x: 0, y: 0.3, z: 0 },     // 2: mushrooms (low, subtle)
  { x: 0, y: 0.2, z: 0 },     // 3: flowers (low, gentle)
  { x: 0, y: 2.5, z: 0 },     // 4: spores (high, maximum drift)
];

const bioluminescent = {
  name: 'Bioluminescent',
  sceneCount: 5,
  samplePoints: BIO_SAMPLE_PTS,
  // How strongly each scene responds to wind [position_scale, scale_response]
  windResponse: [0, 0.5, 0.2, 0.3, 1.0],

  build() {
    const ground = [];
    for (let i = 0; i < 300; i++) {
      const x = (Math.random() - 0.5) * 12, z = (Math.random() - 0.5) * 12;
      const sc = 0.06 + Math.random() * 0.04;
      const c = BIO_PALETTE.GROUND.base;
      ground.push(makeSplat(x, Math.random() * 0.05, z, sc * 2, sc * 0.3, sc * 2,
        c[0] + randn() * 8, c[1] + randn() * 10, c[2] + randn() * 8, 200));
    }

    const trees = [];
    // Per-tree variation: height scale, trunk width, canopy spread, lean
    const treeVariations = [
      { hScale: 1.0,  trunkW: 1.0,  canopySpread: 1.0,  lean: [0, 0],       vineCount: 3 },
      { hScale: 1.25, trunkW: 0.8,  canopySpread: 0.75, lean: [0.15, 0.1],  vineCount: 2 },
      { hScale: 0.7,  trunkW: 1.3,  canopySpread: 1.4,  lean: [-0.1, 0.2],  vineCount: 4 },
      { hScale: 1.4,  trunkW: 0.7,  canopySpread: 0.6,  lean: [0.08, -0.15], vineCount: 1 },
      { hScale: 0.85, trunkW: 1.1,  canopySpread: 1.2,  lean: [-0.2, -0.1], vineCount: 5 },
    ];
    for (let ti = 0; ti < BIO_TREE_POS.length; ti++) {
      const [tx, , tz] = BIO_TREE_POS[ti];
      const v = treeVariations[ti % treeVariations.length];
      const h = v.hScale;
      const lx = v.lean[0], lz = v.lean[1];
      // Trunk — extends from ground to canopy
      addCluster(trees, tx + lx * 0.3, 1.5 * h, tz + lz * 0.3,
        0.08 * v.trunkW, 1.5 * h, 0.08 * v.trunkW,
        BIO_PALETTE.TREE.base, Math.round(100 * h), 0.04 * v.trunkW, 180);
      // Roots — spread outward at ground level
      const rootCount = 4 + Math.floor(v.trunkW * 3);
      for (let ri = 0; ri < rootCount; ri++) {
        const angle = (ri / rootCount) * Math.PI * 2 + ti * 0.7;
        const rootLen = 0.3 + Math.random() * 0.5 * v.trunkW;
        const rx = Math.cos(angle) * rootLen;
        const rz = Math.sin(angle) * rootLen;
        addCluster(trees, tx + rx * 0.5, 0.08, tz + rz * 0.5,
          Math.abs(rx) * 0.4 + 0.02, 0.06, Math.abs(rz) * 0.4 + 0.02,
          BIO_PALETTE.TREE.base, Math.round(12 * v.trunkW), 0.035 * v.trunkW, 170);
      }
      // Canopy base
      addCluster(trees, tx + lx, 3.2 * h, tz + lz,
        0.6 * v.canopySpread, 0.3 * v.canopySpread, 0.6 * v.canopySpread,
        BIO_PALETTE.CANOPY.base, Math.round(120 * v.canopySpread), 0.06 * v.canopySpread, 160);
      // Canopy glow
      addCluster(trees, tx + lx, 3.0 * h, tz + lz,
        0.5 * v.canopySpread, 0.25 * v.canopySpread, 0.5 * v.canopySpread,
        BIO_PALETTE.CANOPY.glow, Math.round(30 * v.canopySpread), 0.03 * v.canopySpread, 220);
      // Vines
      for (let vi = 0; vi < v.vineCount; vi++) {
        const vx = tx + lx * 0.5 + (Math.random() - 0.5) * 0.8 * v.canopySpread;
        const vz = tz + lz * 0.5 + (Math.random() - 0.5) * 0.8 * v.canopySpread;
        addCluster(trees, vx, 2.0 * h, vz, 0.02, 0.5 * h, 0.02, BIO_PALETTE.VINE.glow, 20, 0.02, 180);
      }
    }

    const mushrooms = [];
    for (const [mx, , mz] of BIO_MUSHROOM_POS) {
      addCluster(mushrooms, mx, 0.15, mz, 0.02, 0.07, 0.02, BIO_PALETTE.MUSHROOM.base, 15, 0.02, 190);
      addCluster(mushrooms, mx, 0.35, mz, 0.08, 0.03, 0.08, BIO_PALETTE.MUSHROOM.glow, 25, 0.04, 230);
    }

    const flowers = [];
    for (const [fx, , fz] of BIO_FLOWER_POS) {
      const hue = 0.55 + Math.random() * 0.15;
      const [fr, fg, fb] = hslToRgb(hue, 0.8, 0.6);
      addCluster(flowers, fx, 0.2, fz, 0.06, 0.04, 0.06, [fr, fg, fb], 20, 0.025, 210);
    }

    const spores = [];
    for (let i = 0; i < 80; i++) {
      const c = BIO_PALETTE.SPORE.glow;
      spores.push(makeSplat(
        (Math.random() - 0.5) * 10, 1.5 + Math.random() * 3.0, (Math.random() - 0.5) * 10,
        0.015, 0.015, 0.015, c[0], c[1], c[2], 120 + Math.random() * 80
      ));
    }

    return [ground, trees, mushrooms, flowers, spores];
  },

  setupLights(scene) {
    const lights = {};
    lights.ambient = new THREE.AmbientLight(0x101828, 0.15);
    scene.add(lights.ambient);

    lights.mushroom = BIO_MUSHROOM_POS.map(([x, , z]) => {
      const l = new THREE.PointLight(0xb040ff, 0, 6);
      l.position.set(x, 0.5, z);
      scene.add(l);
      return l;
    });

    lights.tree = BIO_TREE_POS.map(([x, , z]) => {
      const l = new THREE.PointLight(0x30c080, 0, 8);
      l.position.set(x, 3.0, z);
      scene.add(l);
      return l;
    });

    lights.spore = new THREE.PointLight(0x80d0ff, 0, 12);
    lights.spore.position.set(0, 2.5, 0);
    scene.add(lights.spore);

    return lights;
  },

  animate(ctx) {
    const { mesh, time, smooth, sensorState, lights, wind = 0, pulse = 0, wv } = ctx;
    if (!mesh || mesh.scenes.length < 5) return;

    const w = wind;
    const p = pulse;
    const bpmNorm = clamp((smooth.bpm - 50) / 130, 0, 1);
    const bps = smooth.bpm / 60.0;
    const heartPhase = time * bps * Math.PI * 2;
    const heartPulse = 0.5 + 0.5 * Math.sin(heartPhase);
    const breathRate = 0.15 + smooth.breathing * 0.1;
    const breathPhase = Math.sin(time * breathRate * Math.PI * 2);
    const accelNorm = clamp(smooth.accelMag / 15, 0, 1);

    // Mushrooms: heartbeat pulse + curl wind + data glow
    const mushroomScene = mesh.getScene(2);
    if (mushroomScene && wv[2]) {
      const sc = 1.0 + 0.06 * heartPulse * (0.5 + bpmNorm * 0.5) + w * wv[2].y * 0.1 + p * 0.1;
      mushroomScene.position.set(wv[2].x * w * 0.2, 0, wv[2].z * w * 0.2);
      mushroomScene.scale.set(1, sc, 1);
    }

    // Spores: IMU drift + curl wind floating + data burst
    const sporeScene = mesh.getScene(4);
    if (sporeScene && wv[4]) {
      const drift = accelNorm * 0.3;
      sporeScene.position.set(
        wv[4].x * w * 1.0 + Math.sin(time * 0.3) * drift,
        wv[4].y * w * 0.4 + p * 0.15,
        wv[4].z * w * 1.0 + Math.cos(time * 0.25) * drift
      );
    }

    // Trees: breathing sway + curl wind sway
    const treeScene = mesh.getScene(1);
    if (treeScene && wv[1]) {
      const breathSway = breathPhase * 0.02;
      treeScene.position.set(
        breathSway + wv[1].x * w * 0.5,
        0,
        breathSway * 0.5 + wv[1].z * w * 0.5
      );
    }

    // Flowers: breathing scale + curl wind bob + data bloom
    const flowerScene = mesh.getScene(3);
    if (flowerScene && wv[3]) {
      const s = 1.0 + breathPhase * 0.03 + w * Math.abs(wv[3].y) * 0.12 + p * 0.06;
      flowerScene.position.set(wv[3].x * w * 0.3, 0, wv[3].z * w * 0.3);
      flowerScene.scale.set(s, s, s);
    }

    // Mushroom lights: heartrate hue + wind glow + data pulse glow
    if (lights.mushroom) {
      const hue = lerp(0.75, 0.88, bpmNorm);
      const [lr, lg, lb] = hslToRgb(hue, 0.9, 0.45 + 0.15 * heartPulse);
      const baseIntensity = w * 0.3 + bpmNorm * 0.7;
      for (let i = 0; i < lights.mushroom.length; i++) {
        const stagger = Math.sin(heartPhase + i * 0.9) * 0.5 + 0.5;
        lights.mushroom[i].intensity = baseIntensity * (0.4 + 0.6 * stagger) + p * 0.8;
        lights.mushroom[i].color.setRGB(lr / 255, lg / 255, lb / 255);
      }
    }

    // Tree lights: breathing hue + data glow
    if (lights.tree) {
      const breathHue = lerp(0.35, 0.45, clamp(smooth.breathing, 0, 1));
      const [tr, tg, tb] = hslToRgb(breathHue, 0.7, 0.5);
      for (let i = 0; i < lights.tree.length; i++) {
        const phase = Math.sin(time * breathRate * Math.PI * 2 + i * 1.2);
        lights.tree[i].intensity = w * 0.15 + 0.2 + 0.4 * (0.5 + 0.5 * phase) + p * 0.5;
        lights.tree[i].color.setRGB(tr / 255, tg / 255, tb / 255);
      }
    }

    // Spore light: IMU movement + data glow
    if (lights.spore) {
      const moveHue = lerp(0.55, 0.12, accelNorm);
      const [sr, sg, sb] = hslToRgb(moveHue, 0.8, 0.55);
      lights.spore.intensity = w * 0.2 + 0.15 + accelNorm * 0.6 + p * 0.6;
      lights.spore.color.setRGB(sr / 255, sg / 255, sb / 255);
      if (wv[4]) {
        lights.spore.position.x = wv[4].x * w * 2 + accelNorm * Math.sin(time * 2) * 0.5;
        lights.spore.position.z = wv[4].z * w * 2;
        lights.spore.position.y = 2.5 + wv[4].y * w * 0.5;
      }
    }

    // Ambient: sensor presence + wind + data glow
    if (lights.ambient) {
      const presence = clamp(sensorState.sensorCount / 5, 0, 1);
      lights.ambient.intensity = 0.08 + w * 0.15 + presence * 0.22 + p * 0.3;
    }

    mesh.updateTransforms();
  }
};

// ============================================================================
// WORLD: Inferno (volcanic fire landscape)
// ============================================================================

const FIRE_COL_POS = [[-2.0, 0, -1.5], [1.5, 0, -2.0], [0.0, 0, 2.0], [2.5, 0, 0.5], [-3.0, 0, 1.0]];
const ROCK_POS = [[-1.5, 0, 0.5], [1.0, 0, -0.8], [-2.5, 0, 2.5], [3.0, 0, -1.5],
                  [0.5, 0, -3.0], [-3.5, 0, -0.5], [2.0, 0, 2.5], [-0.5, 0, -2.0]];

const INF_SAMPLE_PTS = [
  { x: 0, y: 0, z: 0 },       // 0: lava ground (static)
  { x: 0, y: 1.5, z: 0 },     // 1: fire columns (medium)
  { x: 0, y: 2.5, z: 0 },     // 2: embers (high, turbulent)
  { x: 0, y: 0.3, z: 0 },     // 3: rocks (static)
  { x: 0, y: 3.5, z: 0 },     // 4: smoke (highest, maximum drift)
];

const inferno = {
  name: 'Inferno',
  sceneCount: 5,
  samplePoints: INF_SAMPLE_PTS,
  windResponse: [0, 0.4, 0.8, 0, 1.0],

  build() {
    const ground = [];
    for (let i = 0; i < 350; i++) {
      const x = (Math.random() - 0.5) * 12, z = (Math.random() - 0.5) * 12;
      const sc = 0.06 + Math.random() * 0.04;
      const isLava = Math.random() < 0.2;
      const c = isLava ? [200 + randn() * 20, 80 + randn() * 20, 10] : [25 + randn() * 8, 20 + randn() * 5, 18 + randn() * 5];
      ground.push(makeSplat(x, Math.random() * 0.05, z, sc * 2, sc * 0.3, sc * 2,
        c[0], c[1], c[2], isLava ? 230 : 200));
    }

    const columns = [];
    for (const [fx, , fz] of FIRE_COL_POS) {
      const height = 2.0 + Math.random() * 1.5;
      for (let y = 0; y < height; y += 0.1) {
        const t = y / height;
        const [r, g, b] = hslToRgb(lerp(0.02, 0.12, t), 1.0, lerp(0.35, 0.6, t));
        const spread = 0.15 * (1 - t * 0.5);
        const count = Math.round(3 + (1 - t) * 4);
        addCluster(columns, fx, y, fz, spread, 0.05, spread, [r, g, b], count, 0.025 + t * 0.01, 200 - t * 60);
      }
    }

    const embers = [];
    for (let i = 0; i < 120; i++) {
      const [r, g, b] = hslToRgb(Math.random() * 0.08, 1.0, 0.5 + Math.random() * 0.2);
      embers.push(makeSplat(
        (Math.random() - 0.5) * 10, 0.5 + Math.random() * 4.0, (Math.random() - 0.5) * 10,
        0.012, 0.012, 0.012, r, g, b, 150 + Math.random() * 80
      ));
    }

    const rocks = [];
    for (const [rx, , rz] of ROCK_POS) {
      const rh = 0.3 + Math.random() * 0.5;
      addCluster(rocks, rx, rh * 0.5, rz, 0.15, rh * 0.3, 0.15,
        [30 + randn() * 10, 25 + randn() * 8, 22 + randn() * 8], 25, 0.05, 210);
    }

    const smoke = [];
    for (const [fx, , fz] of FIRE_COL_POS) {
      for (let i = 0; i < 15; i++) {
        const y = 2.5 + Math.random() * 3.0;
        const gray = 40 + randn() * 15;
        smoke.push(makeSplat(
          fx + randn() * 0.5, y, fz + randn() * 0.5,
          0.08 + Math.random() * 0.06, 0.04, 0.08 + Math.random() * 0.06,
          gray, gray, gray, 60 + Math.random() * 40
        ));
      }
    }

    return [ground, columns, embers, rocks, smoke];
  },

  setupLights(scene) {
    const lights = {};
    lights.ambient = new THREE.AmbientLight(0x1a0800, 0.12);
    scene.add(lights.ambient);

    lights.fire = FIRE_COL_POS.map(([x, , z]) => {
      const l = new THREE.PointLight(0xff4400, 0, 8);
      l.position.set(x, 1.5, z);
      scene.add(l);
      return l;
    });

    lights.lava = new THREE.PointLight(0xff2200, 0, 15);
    lights.lava.position.set(0, 0.2, 0);
    scene.add(lights.lava);

    return lights;
  },

  animate(ctx) {
    const { mesh, time, smooth, sensorState, lights, wind = 0, pulse = 0, wv } = ctx;
    if (!mesh || mesh.scenes.length < 5) return;

    const w = wind;
    const p = pulse;
    const bpmNorm = clamp((smooth.bpm - 50) / 130, 0, 1);
    const bps = smooth.bpm / 60.0;
    const heartPhase = time * bps * Math.PI * 2;
    const heartPulse = 0.5 + 0.5 * Math.sin(heartPhase);
    const breathRate = 0.15 + smooth.breathing * 0.1;
    const breathPhase = Math.sin(time * breathRate * Math.PI * 2);
    const accelNorm = clamp(smooth.accelMag / 15, 0, 1);

    // Fire columns: heartbeat pulse + curl wind flicker + data surge
    const colScene = mesh.getScene(1);
    if (colScene && wv[1]) {
      const sc = 1.0 + 0.1 * heartPulse * (0.5 + bpmNorm * 0.5) + p * 0.15;
      colScene.scale.set(1, sc, 1);
      colScene.position.set(
        wv[1].x * w * 0.4 + Math.sin(time * 1.5) * 0.05,
        0,
        wv[1].z * w * 0.4 + Math.cos(time * 1.3) * 0.05
      );
    }

    // Embers: IMU turbulence + curl wind rise + data burst
    const emberScene = mesh.getScene(2);
    if (emberScene && wv[2]) {
      const turb = accelNorm * 0.3;
      emberScene.position.set(
        wv[2].x * w * 0.8 + Math.sin(time * 0.8) * turb,
        wv[2].y * w * 0.5 + p * 0.15,
        wv[2].z * w * 0.8 + Math.cos(time * 0.6) * turb
      );
    }

    // Smoke: breathing drift + curl wind continuous rise
    const smokeScene = mesh.getScene(4);
    if (smokeScene && wv[4]) {
      smokeScene.position.set(
        wv[4].x * w * 0.6 + breathPhase * 0.04,
        wv[4].y * w * 0.4 + breathPhase * 0.08,
        wv[4].z * w * 0.6
      );
    }

    // Fire lights: heartrate flicker + data pulse
    if (lights.fire) {
      const hue = lerp(0.06, 0.01, bpmNorm);
      const [lr, lg, lb] = hslToRgb(hue, 1.0, 0.4 + 0.15 * heartPulse);
      for (let i = 0; i < lights.fire.length; i++) {
        const flicker = Math.sin(heartPhase + i * 1.3) * 0.5 + 0.5;
        const turbFlicker = Math.sin(time * 8 + i * 2.7) * 0.15;
        lights.fire[i].intensity = w * 0.4 + (0.5 + bpmNorm * 0.8) * (0.5 + 0.5 * flicker) + turbFlicker + p * 1.0;
        lights.fire[i].color.setRGB(lr / 255, lg / 255, lb / 255);
      }
    }

    // Lava glow: breathing + wind + data pulse
    if (lights.lava) {
      lights.lava.intensity = w * 0.2 + 0.3 + 0.4 * (0.5 + 0.5 * breathPhase) + p * 0.6;
      const lavaHue = lerp(0.04, 0.01, bpmNorm);
      const [r, g, b] = hslToRgb(lavaHue, 1.0, 0.35);
      lights.lava.color.setRGB(r / 255, g / 255, b / 255);
    }

    if (lights.ambient) {
      const presence = clamp(sensorState.sensorCount / 5, 0, 1);
      lights.ambient.intensity = 0.05 + w * 0.15 + presence * 0.15 + p * 0.3;
    }

    mesh.updateTransforms();
  }
};

// ============================================================================
// WORLD: Meadow (pastoral grass & wildflower landscape)
// ============================================================================

const GRASS_POS = [[-2.0, 0, -1.0], [1.5, 0, -2.5], [-0.5, 0, 2.0], [3.0, 0, 0.0], [-3.0, 0, 1.5], [1.0, 0, 1.5]];
const WILDFLOWER_POS = [[-1.5, 0, 0.5], [0.8, 0, -1.5], [-2.5, 0, 2.5], [2.0, 0, -0.5],
                        [0.0, 0, -2.5], [-3.0, 0, -1.0], [1.5, 0, 2.0], [3.5, 0, 1.5],
                        [-1.0, 0, -1.5], [0.5, 0, 3.0]];

const MDW_SAMPLE_PTS = [
  { x: 0, y: 0, z: 0 },       // 0: ground (static)
  { x: 0, y: 0.4, z: 0 },     // 1: grass (low, swaying)
  { x: 0, y: 0.2, z: 0 },     // 2: flowers (low, gentle)
  { x: 0, y: 1.2, z: 0 },     // 3: butterflies (medium, fluttery)
  { x: 0, y: 0.3, z: 0 },     // 4: hills (static)
];

const meadow = {
  name: 'Meadow',
  sceneCount: 5,
  samplePoints: MDW_SAMPLE_PTS,
  windResponse: [0, 0.6, 0.3, 0.9, 0],

  build() {
    const ground = [];
    for (let i = 0; i < 400; i++) {
      const x = (Math.random() - 0.5) * 12, z = (Math.random() - 0.5) * 12;
      const hill = Math.sin(x * 0.5) * Math.cos(z * 0.4) * 0.15;
      const sc = 0.05 + Math.random() * 0.04;
      const greenVar = Math.random();
      const c = [30 + greenVar * 40 + randn() * 10, 120 + greenVar * 60 + randn() * 15, 20 + greenVar * 30 + randn() * 10];
      ground.push(makeSplat(x, hill + Math.random() * 0.03, z, sc * 2, sc * 0.25, sc * 2,
        c[0], c[1], c[2], 210));
    }

    const grass = [];
    for (const [gx, , gz] of GRASS_POS) {
      const h = 0.4 + Math.random() * 0.3;
      addCluster(grass, gx, h * 0.5, gz, 0.08, h * 0.4, 0.08,
        [40 + randn() * 15, 160 + randn() * 20, 30 + randn() * 15], 40, 0.02, 190);
      addCluster(grass, gx, h, gz, 0.1, 0.05, 0.1,
        [60 + randn() * 10, 180 + randn() * 15, 40 + randn() * 10], 15, 0.015, 170);
    }

    const flowers = [];
    for (const [fx, , fz] of WILDFLOWER_POS) {
      const hue = Math.random();
      const [r, g, b] = hslToRgb(hue, 0.7, 0.65);
      addCluster(flowers, fx, 0.2, fz, 0.04, 0.03, 0.04, [r, g, b], 12, 0.02, 220);
      addCluster(flowers, fx, 0.08, fz, 0.02, 0.06, 0.02,
        [30 + randn() * 10, 100 + randn() * 15, 20 + randn() * 10], 5, 0.01, 180);
    }

    const butterflies = [];
    for (let i = 0; i < 50; i++) {
      const hue = Math.random();
      const [r, g, b] = hslToRgb(hue, 0.9, 0.6);
      const x = (Math.random() - 0.5) * 8, z = (Math.random() - 0.5) * 8;
      butterflies.push(makeSplat(x, 0.5 + Math.random() * 2.0, z,
        0.015, 0.008, 0.02, r, g, b, 180 + Math.random() * 50));
    }

    const hills = [];
    const hillCenters = [[-4, 0, -3], [4, 0, -2], [-3, 0, 4], [5, 0, 3], [0, 0, -5]];
    for (const [hx, , hz] of hillCenters) {
      const height = 0.3 + Math.random() * 0.4;
      addCluster(hills, hx, height * 0.4, hz, 1.5, height * 0.3, 1.5,
        [50 + randn() * 15, 100 + randn() * 20, 30 + randn() * 10], 50, 0.1, 180);
    }

    return [ground, grass, flowers, butterflies, hills];
  },

  setupLights(scene) {
    const lights = {};

    lights.ambient = new THREE.AmbientLight(0x87ceeb, 0.35);
    scene.add(lights.ambient);

    lights.sun = new THREE.DirectionalLight(0xfff5e0, 0.6);
    lights.sun.position.set(5, 8, 3);
    scene.add(lights.sun);

    lights.flower = WILDFLOWER_POS.slice(0, 5).map(([x, , z]) => {
      const l = new THREE.PointLight(0xffaacc, 0, 4);
      l.position.set(x, 0.5, z);
      scene.add(l);
      return l;
    });

    lights.butterfly = new THREE.PointLight(0xffee88, 0, 10);
    lights.butterfly.position.set(0, 1.5, 0);
    scene.add(lights.butterfly);

    return lights;
  },

  animate(ctx) {
    const { mesh, time, smooth, sensorState, lights, wind = 0, pulse = 0, wv } = ctx;
    if (!mesh || mesh.scenes.length < 5) return;

    const w = wind;
    const p = pulse;
    const bpmNorm = clamp((smooth.bpm - 50) / 130, 0, 1);
    const bps = smooth.bpm / 60.0;
    const heartPhase = time * bps * Math.PI * 2;
    const heartPulse = 0.5 + 0.5 * Math.sin(heartPhase);
    const breathRate = 0.15 + smooth.breathing * 0.1;
    const breathPhase = Math.sin(time * breathRate * Math.PI * 2);
    const accelNorm = clamp(smooth.accelMag / 15, 0, 1);

    // Grass sway: breathing + curl wind
    const grassScene = mesh.getScene(1);
    if (grassScene && wv[1]) {
      const breathSway = breathPhase * 0.04;
      grassScene.position.set(
        breathSway + wv[1].x * w * 0.6,
        0,
        breathSway * 0.7 + wv[1].z * w * 0.6
      );
    }

    // Flowers: heartbeat bloom + curl wind bob + data bloom
    const flowerScene = mesh.getScene(2);
    if (flowerScene && wv[2]) {
      const bloom = 1.0 + 0.06 * heartPulse * (0.3 + bpmNorm * 0.7) + p * 0.08;
      flowerScene.position.set(wv[2].x * w * 0.3, 0, wv[2].z * w * 0.3);
      flowerScene.scale.set(bloom, bloom, bloom);
    }

    // Butterflies: IMU scatter + curl wind flutter + data burst
    const butterflyScene = mesh.getScene(3);
    if (butterflyScene && wv[3]) {
      const scatter = accelNorm * 0.3;
      butterflyScene.position.set(
        wv[3].x * w * 0.9 + Math.sin(time * 0.5) * scatter,
        wv[3].y * w * 0.4 + p * 0.1,
        wv[3].z * w * 0.9 + Math.cos(time * 0.4) * scatter
      );
    }

    // Sun: breathing intensity + data flash
    if (lights.sun) {
      const sunHue = lerp(0.12, 0.15, bpmNorm);
      const [r, g, b] = hslToRgb(sunHue, 0.3, 0.9);
      lights.sun.color.setRGB(r / 255, g / 255, b / 255);
      lights.sun.intensity = 0.5 + 0.3 * breathPhase * 0.5 + p * 0.4;
    }

    // Flower lights: heartrate glow + data pulse
    if (lights.flower) {
      for (let i = 0; i < lights.flower.length; i++) {
        const phase = Math.sin(heartPhase + i * 1.1) * 0.5 + 0.5;
        lights.flower[i].intensity = w * 0.15 + 0.1 + 0.3 * phase * bpmNorm + p * 0.5;
      }
    }

    // Butterfly light: IMU + wind drift + data glow
    if (lights.butterfly) {
      lights.butterfly.intensity = w * 0.15 + 0.1 + accelNorm * 0.4 + p * 0.4;
      if (wv[3]) {
        lights.butterfly.position.x = wv[3].x * w * 2;
        lights.butterfly.position.z = wv[3].z * w * 2;
        lights.butterfly.position.y = 1.5 + wv[3].y * w * 0.5;
      }
    }

    if (lights.ambient) {
      const presence = clamp(sensorState.sensorCount / 5, 0, 1);
      lights.ambient.intensity = 0.25 + w * 0.15 + presence * 0.2 + p * 0.3;
    }

    mesh.updateTransforms();
  }
};

// ============================================================================
// World Registry
// ============================================================================

const WORLDS = { bioluminescent, inferno, meadow };

// ============================================================================
// Hook
// ============================================================================

const AvatarSplatHook = {
  mounted() {
    this.viewer = null;
    this.initRetryCount = 0;
    this.time = 0;
    this._blobUrls = [];
    this._lights = {};
    this._particles = null;
    this._windField = new WindField();
    this._worldKey = this.el.dataset.world || 'bioluminescent';
    this._world = WORLDS[this._worldKey] || WORLDS.bioluminescent;

    this.sensorState = { bpm: 70, breathing: 0.5, accelMag: 0, sensorCount: 0, yaw: 0, pitch: 0 };
    this.smooth = { bpm: 70, breathing: 0.5, accelMag: 0, yaw: 0, pitch: 0 };
    this.sensorStates = new Map();
    this._cameraRadius = 6.0;
    this._cameraLookAt = { x: 0, y: 1.5, z: 0 };
    this._sensorDriven = false;
    this.wind = 0.5;
    this.dataPulse = 0;
    this._dt = 0;

    this._onMeasurement = this._handleMeasurementEvent.bind(this);
    window.addEventListener('composite-measurement-event', this._onMeasurement);

    this._handleResize = () => {
      if (this.viewer?.renderer) {
        const rect = this.el.getBoundingClientRect();
        if (rect.width > 0 && rect.height > 0) {
          this.viewer.renderer.setSize(rect.width, rect.height);
        }
      }
    };
    window.addEventListener('resize', this._handleResize);

    this.handleEvent('avatar_enter_fullscreen', () => {
      const container = this.el.closest('#avatar-splat-container') || this.el;
      if (container.requestFullscreen) container.requestFullscreen();
    });
    this.handleEvent('avatar_exit_fullscreen', () => {
      if (document.fullscreenElement) document.exitFullscreen();
    });
    this._onFullscreenChange = () => {
      const isFullscreen = !!document.fullscreenElement;
      this.pushEvent('avatar_fullscreen_changed', { fullscreen: isFullscreen });
      if (this.viewer?.renderer) {
        const container = document.fullscreenElement || this.el;
        const rect = container.getBoundingClientRect();
        if (rect.width > 0 && rect.height > 0) {
          this.viewer.renderer.setSize(rect.width, rect.height);
        }
      }
    };
    document.addEventListener('fullscreenchange', this._onFullscreenChange);

    this.handleEvent('avatar_switch_world', ({ world }) => {
      if (world && WORLDS[world] && world !== this._worldKey) {
        this._switchWorld(world);
      }
    });

    this.handleEvent('avatar_set_wind', ({ value }) => {
      this.wind = clamp(value, 0, 1);
    });

    this.handleEvent('avatar_update_camera', ({ position, target }) => {
      if (!this.viewer || this._sensorDriven) return;
      const controls = this.viewer.perspectiveControls || this.viewer.controls;
      if (controls) controls.enabled = false;
      const cam = this.viewer.camera;
      cam.position.set(position[0], position[1], position[2]);
      cam.lookAt(target[0], target[1], target[2]);
      if (controls?.target) controls.target.set(target[0], target[1], target[2]);
      if (controls) {
        controls.update?.();
        requestAnimationFrame(() => { controls.enabled = true; });
      }
    });

    this._lastCameraPush = 0;
    this._tryInit();
  },

  async _switchWorld(worldKey) {
    console.log(`[AvatarSplat] Switching to world: ${worldKey}`);
    this._worldKey = worldKey;
    this._world = WORLDS[worldKey];

    if (this._particles) {
      this._particles.dispose();
      this._particles = null;
    }
    if (this._blobUrls) {
      for (const url of this._blobUrls) URL.revokeObjectURL(url);
      this._blobUrls = [];
    }
    if (this._canvasObserver) {
      this._canvasObserver.disconnect();
      this._canvasObserver = null;
    }
    if (this._rafId) {
      cancelAnimationFrame(this._rafId);
      this._rafId = null;
    }
    if (this.viewer) {
      try { this.viewer.dispose(); } catch (_) {}
      this.viewer = null;
    }
    this._lights = {};
    this.time = 0;

    const canvases = this.el.querySelectorAll('canvas');
    canvases.forEach(c => c.remove());

    this.initRetryCount = 0;
    this._tryInit();
  },

  _tryInit() {
    const rect = this.el.getBoundingClientRect();
    if (rect.width === 0 || rect.height === 0) {
      if (this.initRetryCount++ < 50) setTimeout(() => this._tryInit(), 100);
      return;
    }
    this._initViewer();
  },

  async _initViewer() {
    try {
      this.viewer = new GaussianSplats3D.Viewer({
        cameraUp: [0, 1, 0],
        initialCameraPosition: [0, 2.0, 6.0],
        initialCameraLookAt: [0, 1.5, 0],
        rootElement: this.el,
        selfDrivenMode: true,
        useBuiltInControls: true,
        dynamicScene: true,
        antialiased: true,
        sharedMemoryForWorkers: false,
      });

      const fixCanvas = (canvas) => {
        if (canvas) {
          canvas.style.position = 'absolute';
          canvas.style.top = '0';
          canvas.style.left = '0';
          canvas.style.width = '100%';
          canvas.style.height = '100%';
          canvas.style.zIndex = '10';
        }
      };
      fixCanvas(this.el.querySelector('canvas'));
      this._canvasObserver = new MutationObserver((mutations) => {
        for (const m of mutations)
          for (const node of m.addedNodes)
            if (node.tagName === 'CANVAS') fixCanvas(node);
      });
      this._canvasObserver.observe(this.el, { childList: true });

      for (const c of [this.viewer?.perspectiveControls, this.viewer?.orthographicControls])
        if (c?.stopListenToKeyEvents) c.stopListenToKeyEvents();
      setTimeout(() => {
        for (const c of [this.viewer?.perspectiveControls, this.viewer?.orthographicControls])
          if (c?.stopListenToKeyEvents) c.stopListenToKeyEvents();
      }, 0);

      console.log(`[AvatarSplat] Loading ${this._world.name} world...`);
      const groups = this._world.build();
      for (const g of groups) {
        const blob = splatsToPlyBlob(g);
        const url = URL.createObjectURL(blob);
        this._blobUrls.push(url);
        await this.viewer.addSplatScene(url, {
          format: 2, splatAlphaRemovalThreshold: 1, showLoadingUI: false,
          position: [0, 0, 0], rotation: [0, 0, 0, 1], scale: [1, 1, 1],
        });
      }
      this.viewer.start();

      const total = this.viewer.splatMesh?.getSplatCount?.() || 0;
      console.log(`[AvatarSplat] ${this._world.name}: ${groups.length} scenes, ${total} splats`);

      if (this.viewer.threeScene) {
        this._lights = this._world.setupLights(this.viewer.threeScene);
        this._particles = new WindParticles(this.viewer.threeScene, this._worldKey);
      }

      // Throttled camera sync broadcast on OrbitControls change
      const controls = this.viewer.perspectiveControls || this.viewer.controls;
      if (controls) {
        controls.addEventListener('change', () => {
          const now = performance.now();
          if (now - this._lastCameraPush < 100) return; // 10 Hz max
          this._lastCameraPush = now;
          const cam = this.viewer.camera;
          const tgt = controls.target || { x: 0, y: 1.5, z: 0 };
          this.pushEvent('avatar_camera_changed', {
            position: [cam.position.x, cam.position.y, cam.position.z],
            target: [tgt.x, tgt.y, tgt.z],
          });
        });
      }

      // Own RAF loop for animation — viewer's selfDrivenUpdate handles rendering
      this._lastTime = performance.now();
      const hook = this;
      const animLoop = () => {
        if (!hook.viewer) return;
        const now = performance.now();
        const dt = (now - hook._lastTime) / 1000;
        hook._lastTime = now;
        hook._dt = dt;
        hook.time += dt;
        hook._animate();
        hook.viewer.forceRenderNextFrame();
        hook._rafId = requestAnimationFrame(animLoop);
      };
      this._rafId = requestAnimationFrame(animLoop);
      this.el.__avatarHook = this;

      console.log(`[AvatarSplat] ${this._world.name} ready with wind particles`);
    } catch (error) {
      console.error('[AvatarSplat] Init error:', error);
    }
  },

  _handleMeasurementEvent(e) {
    const { sensor_id, attribute_id, payload } = e.detail;
    if (!this.sensorStates.has(sensor_id)) this.sensorStates.set(sensor_id, {});
    const state = this.sensorStates.get(sensor_id);
    const data = typeof payload === 'string' ? JSON.parse(payload) : payload;

    switch (attribute_id) {
      case 'heartrate':
      case 'hr':
        state.bpm = data?.bpm ?? data?.heartRate ?? data ?? 70;
        break;
      case 'respiration':
        state.breathing = typeof data === 'number' ? data : (data?.value ?? 0.5);
        break;
      case 'imu':
        if (data?.accelerometer) {
          const a = data.accelerometer;
          state.accelMag = Math.sqrt((a.x || 0) ** 2 + (a.y || 0) ** 2 + (a.z || 0) ** 2);
        }
        break;
      case 'quaternion': {
        const q = new THREE.Quaternion(data?.x ?? 0, data?.y ?? 0, data?.z ?? 0, data?.w ?? 1);
        const euler = new THREE.Euler().setFromQuaternion(q, 'YXZ');
        state.yaw = euler.y;
        state.pitch = clamp(euler.x, -Math.PI / 3, Math.PI / 3);
        state.hasOrientation = true;
        break;
      }
      case 'euler': {
        state.yaw = data?.yaw ?? data?.y ?? 0;
        state.pitch = clamp(data?.pitch ?? data?.x ?? 0, -Math.PI / 3, Math.PI / 3);
        state.hasOrientation = true;
        break;
      }
    }
    this._aggregateSensorState();
    this.dataPulse = Math.min(1, this.dataPulse + 0.3);
  },

  _aggregateSensorState() {
    let totalBpm = 0, totalBreathing = 0, totalAccel = 0, count = 0;
    let orientationFound = false;
    for (const [, st] of this.sensorStates) {
      if (st.bpm) { totalBpm += st.bpm; count++; }
      if (st.breathing !== undefined) totalBreathing += st.breathing;
      if (st.accelMag) totalAccel += st.accelMag;
      if (st.hasOrientation && !orientationFound) {
        this.sensorState.yaw = st.yaw;
        this.sensorState.pitch = st.pitch;
        orientationFound = true;
      }
    }
    this._sensorDriven = orientationFound;
    const n = Math.max(1, count);
    this.sensorState.bpm = totalBpm / n || 70;
    this.sensorState.breathing = totalBreathing / n || 0.5;
    this.sensorState.accelMag = totalAccel / n || 0;
    this.sensorState.sensorCount = this.sensorStates.size;
  },

  _animate() {
    const mesh = this.viewer?.splatMesh;
    const dt = this._dt;

    // Decay data pulse
    this.dataPulse = Math.max(0, this.dataPulse - 0.02);

    const alpha = 0.05;
    this.smooth.bpm = lerp(this.smooth.bpm, this.sensorState.bpm, alpha);
    this.smooth.breathing = lerp(this.smooth.breathing, this.sensorState.breathing, alpha);
    this.smooth.accelMag = lerp(this.smooth.accelMag, this.sensorState.accelMag, alpha * 2);
    this.smooth.yaw = lerp(this.smooth.yaw, this.sensorState.yaw, alpha * 3);
    this.smooth.pitch = lerp(this.smooth.pitch, this.sensorState.pitch, alpha * 3);

    // Gust-modulated effective wind
    const gustMul = this._windField.gust(this.time);
    const effectiveWind = this.wind * gustMul;

    // Pre-sample curl noise at each scene's conceptual position
    const wv = [];
    if (this._world?.samplePoints) {
      for (const pt of this._world.samplePoints) {
        wv.push(this._windField.curl(pt.x, pt.y, pt.z, this.time));
      }
    }

    // Camera orbit driven by controller sensor orientation
    if (this._sensorDriven && this.viewer) {
      const controls = this.viewer.perspectiveControls || this.viewer.controls;
      if (controls) controls.enabled = false;

      const cam = this.viewer.camera;
      const r = this._cameraRadius;
      const azimuth = this.smooth.yaw;
      const polar = clamp(Math.PI / 2 - this.smooth.pitch, 0.3, Math.PI - 0.3);
      const cx = r * Math.sin(polar) * Math.sin(azimuth);
      const cy = r * Math.cos(polar);
      const cz = r * Math.sin(polar) * Math.cos(azimuth);

      const la = this._cameraLookAt;
      cam.position.set(la.x + cx, la.y + cy, la.z + cz);
      cam.lookAt(la.x, la.y, la.z);
    } else if (this.viewer) {
      const controls = this.viewer.perspectiveControls || this.viewer.controls;
      if (controls) controls.enabled = true;
    }

    // Delegate world-specific animation with curl noise vectors
    if (this._world && mesh) {
      this._world.animate({
        mesh, time: this.time, smooth: this.smooth,
        sensorState: this.sensorState, lights: this._lights, viewer: this.viewer,
        wind: effectiveWind, pulse: this.dataPulse, wv,
      });
    }

    // Update wind particles
    if (this._particles) {
      this._particles.update(dt, this.time, effectiveWind, this._windField, this.dataPulse);
    }
  },

  destroyed() {
    if (this._rafId) {
      cancelAnimationFrame(this._rafId);
      this._rafId = null;
    }
    if (this._onMeasurement) window.removeEventListener('composite-measurement-event', this._onMeasurement);
    if (this._handleResize) window.removeEventListener('resize', this._handleResize);
    if (this._onFullscreenChange) document.removeEventListener('fullscreenchange', this._onFullscreenChange);

    if (this._canvasObserver) {
      this._canvasObserver.disconnect();
      this._canvasObserver = null;
    }
    if (this._particles) {
      this._particles.dispose();
      this._particles = null;
    }
    if (this._blobUrls) {
      for (const url of this._blobUrls) URL.revokeObjectURL(url);
      this._blobUrls = [];
    }

    if (this.viewer) {
      try { this.viewer.dispose(); } catch (_) {}
      this.viewer = null;
    }
    this._lights = {};
  }
};

export default AvatarSplatHook;
