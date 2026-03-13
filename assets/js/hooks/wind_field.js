import { createNoise4D } from 'simplex-noise';

// Curl noise wind field with multi-octave turbulence.
// Produces divergence-free (incompressible) vector fields
// that create natural swirling, vortex-like flow patterns.

export class WindField {
  constructor() {
    // Three independent 4D noise fields for curl computation.
    // Each createNoise4D() call generates a unique permutation table.
    this._n1 = createNoise4D();
    this._n2 = createNoise4D();
    this._n3 = createNoise4D();
  }

  // Full curl noise — divergence-free 3D vector field.
  // Use for scene-level movement (few samples per frame).
  // Returns {x, y, z} velocity vector.
  curl(x, y, z, time, scale = 0.35) {
    const e = 0.01;
    const tBase = time * 0.12;
    let vx = 0, vy = 0, vz = 0;
    let freq = scale, amp = 1.0, totalAmp = 0;

    for (let o = 0; o < 3; o++) {
      const fx = x * freq, fy = y * freq, fz = z * freq;
      const t = tBase * (1 + o * 0.3);

      // Central finite differences of three noise fields
      const dF3dy = (this._n3(fx, fy + e, fz, t) - this._n3(fx, fy - e, fz, t)) / (2 * e);
      const dF2dz = (this._n2(fx, fy, fz + e, t) - this._n2(fx, fy, fz - e, t)) / (2 * e);
      const dF1dz = (this._n1(fx, fy, fz + e, t) - this._n1(fx, fy, fz - e, t)) / (2 * e);
      const dF3dx = (this._n3(fx + e, fy, fz, t) - this._n3(fx - e, fy, fz, t)) / (2 * e);
      const dF2dx = (this._n2(fx + e, fy, fz, t) - this._n2(fx - e, fy, fz, t)) / (2 * e);
      const dF1dy = (this._n1(fx, fy + e, fz, t) - this._n1(fx, fy - e, fz, t)) / (2 * e);

      // curl(F) = (dFz/dy - dFy/dz, dFx/dz - dFz/dx, dFy/dx - dFx/dy)
      vx += (dF3dy - dF2dz) * amp;
      vy += (dF1dz - dF3dx) * amp;
      vz += (dF2dx - dF1dy) * amp;

      totalAmp += amp;
      freq *= 2.0;   // lacunarity
      amp *= 0.5;     // persistence
    }

    const inv = 1.0 / totalAmp;
    return { x: vx * inv, y: vy * inv, z: vz * inv };
  }

  // Cheap flow sample — raw noise, NOT divergence-free.
  // Use for particle advection (many samples per frame).
  flow(x, y, z, time) {
    const s = 0.28;
    const t = time * 0.1;
    return {
      x: this._n1(x * s, y * s, z * s, t),
      y: this._n2(x * s, y * s, z * s, t) * 0.5,
      z: this._n3(x * s, y * s, z * s, t),
    };
  }

  // Gust intensity modulator — creates periodic wind bursts.
  // Returns 0.3 .. 1.0
  gust(time) {
    const slow = Math.sin(time * 0.08) * 0.5 + 0.5;
    const med  = Math.sin(time * 0.23 + 1.7) * 0.5 + 0.5;
    const fast = Math.sin(time * 0.67 + 3.1) * 0.5 + 0.5;
    return 0.3 + 0.35 * slow + 0.2 * (med * med) + 0.15 * (fast * fast * fast * fast);
  }
}
