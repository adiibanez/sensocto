import * as GaussianSplats3D from '@mkkellogg/gaussian-splats-3d';
import * as THREE from 'three';

// Multi-world sensor-driven Gaussian Splat ecosystem.
// Each world generates different procedural geometry, lights, and animations
// but all respond to the same sensor data pipeline (heartrate, breathing, IMU).

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

const bioluminescent = {
  name: 'Bioluminescent',
  sceneCount: 5,

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
    for (const [tx, , tz] of BIO_TREE_POS) {
      addCluster(trees, tx, 1.5, tz, 0.08, 0.6, 0.08, BIO_PALETTE.TREE.base, 80, 0.04, 180);
      addCluster(trees, tx, 3.2, tz, 0.6, 0.3, 0.6, BIO_PALETTE.CANOPY.base, 120, 0.06, 160);
      addCluster(trees, tx, 3.0, tz, 0.5, 0.25, 0.5, BIO_PALETTE.CANOPY.glow, 30, 0.03, 220);
      for (let v = 0; v < 3; v++) {
        const vx = tx + (Math.random() - 0.5) * 0.8, vz = tz + (Math.random() - 0.5) * 0.8;
        addCluster(trees, vx, 2.0, vz, 0.02, 0.5, 0.02, BIO_PALETTE.VINE.glow, 20, 0.02, 180);
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
    const { mesh, time, smooth, sensorState, lights } = ctx;
    if (!mesh || mesh.scenes.length < 5) return;

    const bpmNorm = clamp((smooth.bpm - 50) / 130, 0, 1);
    const bps = smooth.bpm / 60.0;
    const heartPhase = time * bps * Math.PI * 2;
    const heartPulse = 0.5 + 0.5 * Math.sin(heartPhase);
    const breathRate = 0.15 + smooth.breathing * 0.1;
    const breathPhase = Math.sin(time * breathRate * Math.PI * 2);
    const accelNorm = clamp(smooth.accelMag / 15, 0, 1);

    const mushroomScene = mesh.getScene(2);
    if (mushroomScene) {
      const pulse = 1.0 + 0.04 * heartPulse * (0.5 + bpmNorm * 0.5);
      mushroomScene.scale.set(1, pulse, 1);
    }

    const sporeScene = mesh.getScene(4);
    if (sporeScene) {
      const drift = accelNorm * 0.15;
      sporeScene.position.set(
        Math.sin(time * 0.2) * (0.05 + drift),
        Math.sin(time * 0.12) * 0.03,
        Math.cos(time * 0.18) * (0.05 + drift)
      );
    }

    const treeScene = mesh.getScene(1);
    if (treeScene) {
      const sway = breathPhase * 0.006;
      treeScene.position.set(sway, 0, sway * 0.5);
    }

    const flowerScene = mesh.getScene(3);
    if (flowerScene) {
      const s = 1.0 + breathPhase * 0.015;
      flowerScene.scale.set(s, s, s);
    }

    if (lights.mushroom) {
      const hue = lerp(0.75, 0.88, bpmNorm);
      const [lr, lg, lb] = hslToRgb(hue, 0.9, 0.45 + 0.15 * heartPulse);
      const baseIntensity = 0.3 + bpmNorm * 0.7;
      for (let i = 0; i < lights.mushroom.length; i++) {
        const light = lights.mushroom[i];
        const stagger = Math.sin(heartPhase + i * 0.9) * 0.5 + 0.5;
        light.intensity = baseIntensity * (0.4 + 0.6 * stagger);
        light.color.setRGB(lr / 255, lg / 255, lb / 255);
      }
    }

    if (lights.tree) {
      const breathHue = lerp(0.35, 0.45, clamp(smooth.breathing, 0, 1));
      const [tr, tg, tb] = hslToRgb(breathHue, 0.7, 0.5);
      for (let i = 0; i < lights.tree.length; i++) {
        const light = lights.tree[i];
        const phase = Math.sin(time * breathRate * Math.PI * 2 + i * 1.2);
        light.intensity = 0.2 + 0.4 * (0.5 + 0.5 * phase);
        light.color.setRGB(tr / 255, tg / 255, tb / 255);
      }
    }

    if (lights.spore) {
      const moveHue = lerp(0.55, 0.12, accelNorm);
      const [sr, sg, sb] = hslToRgb(moveHue, 0.8, 0.55);
      lights.spore.intensity = 0.15 + accelNorm * 0.6;
      lights.spore.color.setRGB(sr / 255, sg / 255, sb / 255);
      lights.spore.position.x = Math.sin(time * 0.3) * 2 + accelNorm * Math.sin(time * 2) * 0.5;
      lights.spore.position.z = Math.cos(time * 0.2) * 2;
      lights.spore.position.y = 2.5 + 0.5 * Math.sin(time * 0.15);
    }

    if (lights.ambient) {
      const presence = clamp(sensorState.sensorCount / 5, 0, 1);
      lights.ambient.intensity = 0.08 + presence * 0.22;
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

const inferno = {
  name: 'Inferno',
  sceneCount: 5,

  build() {
    // Scene 0: Lava ground — dark obsidian with orange/red cracks
    const ground = [];
    for (let i = 0; i < 350; i++) {
      const x = (Math.random() - 0.5) * 12, z = (Math.random() - 0.5) * 12;
      const sc = 0.06 + Math.random() * 0.04;
      const isLava = Math.random() < 0.2;
      const c = isLava ? [200 + randn() * 20, 80 + randn() * 20, 10] : [25 + randn() * 8, 20 + randn() * 5, 18 + randn() * 5];
      ground.push(makeSplat(x, Math.random() * 0.05, z, sc * 2, sc * 0.3, sc * 2,
        c[0], c[1], c[2], isLava ? 230 : 200));
    }

    // Scene 1: Fire columns — tall vertical clusters
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

    // Scene 2: Embers — floating bright particles
    const embers = [];
    for (let i = 0; i < 120; i++) {
      const [r, g, b] = hslToRgb(Math.random() * 0.08, 1.0, 0.5 + Math.random() * 0.2);
      embers.push(makeSplat(
        (Math.random() - 0.5) * 10, 0.5 + Math.random() * 4.0, (Math.random() - 0.5) * 10,
        0.012, 0.012, 0.012, r, g, b, 150 + Math.random() * 80
      ));
    }

    // Scene 3: Obsidian rocks
    const rocks = [];
    for (const [rx, , rz] of ROCK_POS) {
      const rh = 0.3 + Math.random() * 0.5;
      addCluster(rocks, rx, rh * 0.5, rz, 0.15, rh * 0.3, 0.15,
        [30 + randn() * 10, 25 + randn() * 8, 22 + randn() * 8], 25, 0.05, 210);
    }

    // Scene 4: Smoke plumes — translucent dark rising
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
    const { mesh, time, smooth, sensorState, lights } = ctx;
    if (!mesh || mesh.scenes.length < 5) return;

    const bpmNorm = clamp((smooth.bpm - 50) / 130, 0, 1);
    const bps = smooth.bpm / 60.0;
    const heartPhase = time * bps * Math.PI * 2;
    const heartPulse = 0.5 + 0.5 * Math.sin(heartPhase);
    const breathRate = 0.15 + smooth.breathing * 0.1;
    const breathPhase = Math.sin(time * breathRate * Math.PI * 2);
    const accelNorm = clamp(smooth.accelMag / 15, 0, 1);

    // Fire columns: scale pulse with heartbeat (flames grow with exertion)
    const colScene = mesh.getScene(1);
    if (colScene) {
      const pulse = 1.0 + 0.08 * heartPulse * (0.5 + bpmNorm * 0.5);
      colScene.scale.set(1, pulse, 1);
      colScene.position.set(Math.sin(time * 1.5) * 0.02, 0, Math.cos(time * 1.3) * 0.02);
    }

    // Embers: turbulent drift from IMU
    const emberScene = mesh.getScene(2);
    if (emberScene) {
      const turb = accelNorm * 0.2;
      emberScene.position.set(
        Math.sin(time * 0.8) * (0.05 + turb),
        Math.sin(time * 0.3) * 0.05,
        Math.cos(time * 0.6) * (0.05 + turb)
      );
    }

    // Smoke: drift upward with breathing
    const smokeScene = mesh.getScene(4);
    if (smokeScene) {
      const rise = breathPhase * 0.03;
      smokeScene.position.set(breathPhase * 0.01, rise, 0);
    }

    // Fire lights: heartrate → intensity flicker + orange→red hue
    if (lights.fire) {
      const hue = lerp(0.06, 0.01, bpmNorm);
      const [lr, lg, lb] = hslToRgb(hue, 1.0, 0.4 + 0.15 * heartPulse);
      for (let i = 0; i < lights.fire.length; i++) {
        const flicker = Math.sin(heartPhase + i * 1.3) * 0.5 + 0.5;
        const turbFlicker = Math.sin(time * 8 + i * 2.7) * 0.15;
        lights.fire[i].intensity = (0.5 + bpmNorm * 0.8) * (0.5 + 0.5 * flicker) + turbFlicker;
        lights.fire[i].color.setRGB(lr / 255, lg / 255, lb / 255);
      }
    }

    // Lava glow: breathing drives intensity
    if (lights.lava) {
      lights.lava.intensity = 0.3 + 0.4 * (0.5 + 0.5 * breathPhase);
      const lavaHue = lerp(0.04, 0.01, bpmNorm);
      const [r, g, b] = hslToRgb(lavaHue, 1.0, 0.35);
      lights.lava.color.setRGB(r / 255, g / 255, b / 255);
    }

    if (lights.ambient) {
      const presence = clamp(sensorState.sensorCount / 5, 0, 1);
      lights.ambient.intensity = 0.05 + presence * 0.15;
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

const meadow = {
  name: 'Meadow',
  sceneCount: 5,

  build() {
    // Scene 0: Grass ground — varied green base with height undulation
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

    // Scene 1: Grass tufts — tall, swaying clusters
    const grass = [];
    for (const [gx, , gz] of GRASS_POS) {
      const h = 0.4 + Math.random() * 0.3;
      addCluster(grass, gx, h * 0.5, gz, 0.08, h * 0.4, 0.08,
        [40 + randn() * 15, 160 + randn() * 20, 30 + randn() * 15], 40, 0.02, 190);
      addCluster(grass, gx, h, gz, 0.1, 0.05, 0.1,
        [60 + randn() * 10, 180 + randn() * 15, 40 + randn() * 10], 15, 0.015, 170);
    }

    // Scene 2: Wildflowers — varied pastel colors
    const flowers = [];
    for (const [fx, , fz] of WILDFLOWER_POS) {
      const hue = Math.random();
      const [r, g, b] = hslToRgb(hue, 0.7, 0.65);
      addCluster(flowers, fx, 0.2, fz, 0.04, 0.03, 0.04, [r, g, b], 12, 0.02, 220);
      addCluster(flowers, fx, 0.08, fz, 0.02, 0.06, 0.02,
        [30 + randn() * 10, 100 + randn() * 15, 20 + randn() * 10], 5, 0.01, 180);
    }

    // Scene 3: Butterflies — tiny bright splats floating above
    const butterflies = [];
    for (let i = 0; i < 50; i++) {
      const hue = Math.random();
      const [r, g, b] = hslToRgb(hue, 0.9, 0.6);
      const x = (Math.random() - 0.5) * 8, z = (Math.random() - 0.5) * 8;
      butterflies.push(makeSplat(x, 0.5 + Math.random() * 2.0, z,
        0.015, 0.008, 0.02, r, g, b, 180 + Math.random() * 50));
    }

    // Scene 4: Gentle hills (background terrain mounds)
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
    const { mesh, time, smooth, sensorState, lights } = ctx;
    if (!mesh || mesh.scenes.length < 5) return;

    const bpmNorm = clamp((smooth.bpm - 50) / 130, 0, 1);
    const bps = smooth.bpm / 60.0;
    const heartPhase = time * bps * Math.PI * 2;
    const heartPulse = 0.5 + 0.5 * Math.sin(heartPhase);
    const breathRate = 0.15 + smooth.breathing * 0.1;
    const breathPhase = Math.sin(time * breathRate * Math.PI * 2);
    const accelNorm = clamp(smooth.accelMag / 15, 0, 1);

    // Grass sway with breathing
    const grassScene = mesh.getScene(1);
    if (grassScene) {
      const sway = breathPhase * 0.015;
      grassScene.position.set(sway, 0, sway * 0.7);
    }

    // Flowers bloom scale with heartbeat
    const flowerScene = mesh.getScene(2);
    if (flowerScene) {
      const bloom = 1.0 + 0.04 * heartPulse * (0.3 + bpmNorm * 0.7);
      flowerScene.scale.set(bloom, bloom, bloom);
    }

    // Butterflies scatter with IMU
    const butterflyScene = mesh.getScene(3);
    if (butterflyScene) {
      const scatter = accelNorm * 0.2;
      butterflyScene.position.set(
        Math.sin(time * 0.4) * (0.1 + scatter),
        Math.sin(time * 0.25) * 0.08,
        Math.cos(time * 0.35) * (0.1 + scatter)
      );
    }

    // Sun color shifts: warm at rest → bright at exertion
    if (lights.sun) {
      const sunHue = lerp(0.12, 0.15, bpmNorm);
      const [r, g, b] = hslToRgb(sunHue, 0.3, 0.9);
      lights.sun.color.setRGB(r / 255, g / 255, b / 255);
      lights.sun.intensity = 0.5 + 0.3 * breathPhase * 0.5;
    }

    // Flower lights: heartrate-synced gentle glow
    if (lights.flower) {
      for (let i = 0; i < lights.flower.length; i++) {
        const phase = Math.sin(heartPhase + i * 1.1) * 0.5 + 0.5;
        lights.flower[i].intensity = 0.1 + 0.3 * phase * bpmNorm;
      }
    }

    // Butterfly light: IMU drives brightness and drift
    if (lights.butterfly) {
      lights.butterfly.intensity = 0.1 + accelNorm * 0.4;
      lights.butterfly.position.x = Math.sin(time * 0.3) * 2;
      lights.butterfly.position.z = Math.cos(time * 0.25) * 2;
      lights.butterfly.position.y = 1.5 + Math.sin(time * 0.15) * 0.5;
    }

    if (lights.ambient) {
      const presence = clamp(sensorState.sensorCount / 5, 0, 1);
      lights.ambient.intensity = 0.25 + presence * 0.2;
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
    this._worldKey = this.el.dataset.world || 'bioluminescent';
    this._world = WORLDS[this._worldKey] || WORLDS.bioluminescent;

    this.sensorState = { bpm: 70, breathing: 0.5, accelMag: 0, sensorCount: 0, yaw: 0, pitch: 0 };
    this.smooth = { bpm: 70, breathing: 0.5, accelMag: 0, yaw: 0, pitch: 0 };
    this.sensorStates = new Map();
    this._cameraRadius = 6.0;
    this._cameraLookAt = { x: 0, y: 1.5, z: 0 };
    this._sensorDriven = false;

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

    this._tryInit();
  },

  async _switchWorld(worldKey) {
    console.log(`[AvatarSplat] Switching to world: ${worldKey}`);
    this._worldKey = worldKey;
    this._world = WORLDS[worldKey];

    if (this._blobUrls) {
      for (const url of this._blobUrls) URL.revokeObjectURL(url);
      this._blobUrls = [];
    }
    if (this._canvasObserver) {
      this._canvasObserver.disconnect();
      this._canvasObserver = null;
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
      }

      const origUpdate = this.viewer.selfDrivenUpdate.bind(this.viewer);
      this.viewer.selfDrivenUpdate = () => {
        this.time += 0.016;
        this._animate();
        origUpdate();
        if (this._sensorDriven) this.viewer.forceRenderNextFrame();
      };

      console.log(`[AvatarSplat] ${this._world.name} ready`);
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

    const alpha = 0.05;
    this.smooth.bpm = lerp(this.smooth.bpm, this.sensorState.bpm, alpha);
    this.smooth.breathing = lerp(this.smooth.breathing, this.sensorState.breathing, alpha);
    this.smooth.accelMag = lerp(this.smooth.accelMag, this.sensorState.accelMag, alpha * 2);
    this.smooth.yaw = lerp(this.smooth.yaw, this.sensorState.yaw, alpha * 3);
    this.smooth.pitch = lerp(this.smooth.pitch, this.sensorState.pitch, alpha * 3);

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

    // Delegate world-specific animation
    if (this._world && mesh) {
      this._world.animate({
        mesh, time: this.time, smooth: this.smooth,
        sensorState: this.sensorState, lights: this._lights, viewer: this.viewer,
      });
    }
  },

  destroyed() {
    if (this._onMeasurement) window.removeEventListener('composite-measurement-event', this._onMeasurement);
    if (this._handleResize) window.removeEventListener('resize', this._handleResize);
    if (this._onFullscreenChange) document.removeEventListener('fullscreenchange', this._onFullscreenChange);

    if (this._canvasObserver) {
      this._canvasObserver.disconnect();
      this._canvasObserver = null;
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
