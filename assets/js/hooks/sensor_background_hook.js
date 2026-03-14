/**
 * SensorBackgroundHook — full-screen Canvas 2D background for the sign-in page.
 * Visualizes the N most active sensors in real-time with 4 selectable themes.
 * Receives data via push_event("sensor_bg_update") from CustomSignInLive.
 */
import { createNoise3D } from 'simplex-noise';

// ---------- Helpers ----------

function hashCode(str) {
  let h = 0;
  for (let i = 0; i < str.length; i++) {
    h = ((h << 5) - h + str.charCodeAt(i)) | 0;
  }
  return Math.abs(h);
}

function sensorHue(id) {
  return (hashCode(id) * 137) % 360;
}

function sensorPosition(id, w, h) {
  const hash = hashCode(id);
  const x = ((hash * 2654435761) % 10000) / 10000;
  const y = ((hash * 340573321) % 10000) / 10000;
  return { x: x * w * 0.8 + w * 0.1, y: y * h * 0.8 + h * 0.1 };
}

function lerp(a, b, t) {
  return a + (b - a) * t;
}

// ---------- Base Renderer ----------

class BaseRenderer {
  constructor(canvas, ctx) {
    this.canvas = canvas;
    this.ctx = ctx;
    this.w = canvas.width;
    this.h = canvas.height;
    this.sensors = [];
    this.sensorState = new Map(); // smoothed per-sensor state
    this.noise3D = createNoise3D();
  }

  updateSensors(sensors) {
    this.sensors = sensors;
    // Smooth intensity transitions
    for (const s of sensors) {
      const prev = this.sensorState.get(s.id);
      if (prev) {
        prev.targetIntensity = s.intensity;
      } else {
        this.sensorState.set(s.id, {
          id: s.id,
          name: s.name,
          hue: sensorHue(s.id),
          intensity: s.intensity,
          targetIntensity: s.intensity,
          pos: sensorPosition(s.id, this.w, this.h),
        });
      }
    }
    // Remove sensors no longer in list
    const activeIds = new Set(sensors.map(s => s.id));
    for (const [id] of this.sensorState) {
      if (!activeIds.has(id)) {
        this.sensorState.delete(id);
      }
    }
  }

  smoothStep(dt) {
    const alpha = Math.min(1, dt * 3); // ~3Hz smoothing
    for (const [, s] of this.sensorState) {
      s.intensity = lerp(s.intensity, s.targetIntensity, alpha);
    }
  }

  resize(w, h) {
    this.w = w;
    this.h = h;
    // Recalculate positions
    for (const [, s] of this.sensorState) {
      s.pos = sensorPosition(s.id, w, h);
    }
  }

  draw(_elapsed, _dt) {}
  dispose() {}
}

// ---------- Constellation ----------

class ConstellationRenderer extends BaseRenderer {
  draw(elapsed, dt) {
    const { ctx, w, h, noise3D } = this;
    this.smoothStep(dt);

    ctx.clearRect(0, 0, w, h);
    const t = elapsed * 0.001;
    const sensors = [...this.sensorState.values()];

    // Ambient dots when no sensors
    if (sensors.length === 0) {
      this._drawAmbient(t);
      return;
    }

    const lineThreshold = Math.min(w, h) * 0.35;

    // Draw connecting lines
    ctx.globalCompositeOperation = 'lighter';
    for (let i = 0; i < sensors.length; i++) {
      for (let j = i + 1; j < sensors.length; j++) {
        const a = sensors[i];
        const b = sensors[j];
        const ax = a.pos.x + noise3D(a.hue * 0.01, 0, t * 0.3) * 20;
        const ay = a.pos.y + noise3D(0, a.hue * 0.01, t * 0.3) * 20;
        const bx = b.pos.x + noise3D(b.hue * 0.01, 1, t * 0.3) * 20;
        const by = b.pos.y + noise3D(1, b.hue * 0.01, t * 0.3) * 20;
        const dist = Math.hypot(ax - bx, ay - by);
        if (dist < lineThreshold) {
          const opacity = (1 - dist / lineThreshold) * Math.sqrt(a.intensity * b.intensity) * 0.3;
          ctx.strokeStyle = `hsla(${(a.hue + b.hue) / 2}, 60%, 60%, ${opacity})`;
          ctx.lineWidth = 1;
          ctx.beginPath();
          ctx.moveTo(ax, ay);
          ctx.lineTo(bx, by);
          ctx.stroke();
        }
      }
    }

    // Draw glowing dots
    for (const s of sensors) {
      const x = s.pos.x + noise3D(s.hue * 0.01, 0, t * 0.3) * 20;
      const y = s.pos.y + noise3D(0, s.hue * 0.01, t * 0.3) * 20;
      const pulse = 1 + Math.sin(t * 2 + s.hue) * 0.2;
      const radius = (4 + s.intensity * 8) * pulse;
      const alpha = 0.3 + s.intensity * 0.7;

      // Outer glow
      const gradient = ctx.createRadialGradient(x, y, 0, x, y, radius * 3);
      gradient.addColorStop(0, `hsla(${s.hue}, 70%, 65%, ${alpha * 0.6})`);
      gradient.addColorStop(0.5, `hsla(${s.hue}, 70%, 55%, ${alpha * 0.15})`);
      gradient.addColorStop(1, `hsla(${s.hue}, 70%, 50%, 0)`);
      ctx.fillStyle = gradient;
      ctx.beginPath();
      ctx.arc(x, y, radius * 3, 0, Math.PI * 2);
      ctx.fill();

      // Core dot
      ctx.fillStyle = `hsla(${s.hue}, 80%, 70%, ${alpha})`;
      ctx.beginPath();
      ctx.arc(x, y, radius, 0, Math.PI * 2);
      ctx.fill();
    }

    ctx.globalCompositeOperation = 'source-over';
  }

  _drawAmbient(t) {
    const { ctx, w, h, noise3D } = this;
    ctx.globalCompositeOperation = 'lighter';
    for (let i = 0; i < 16; i++) {
      const x = w * (0.1 + 0.8 * ((i * 2654435761 % 10000) / 10000));
      const y = h * (0.1 + 0.8 * ((i * 340573321 % 10000) / 10000));
      const nx = x + noise3D(i * 0.5, 0, t * 0.15) * 40;
      const ny = y + noise3D(0, i * 0.5, t * 0.15) * 40;
      const hue = (i * 137 + 180) % 360;
      const pulse = 1 + Math.sin(t * 0.8 + i * 1.3) * 0.3;
      const alpha = (0.12 + Math.sin(t * 0.5 + i) * 0.06) * pulse;
      const r = 30 * pulse;
      const gradient = ctx.createRadialGradient(nx, ny, 0, nx, ny, r);
      gradient.addColorStop(0, `hsla(${hue}, 60%, 65%, ${alpha})`);
      gradient.addColorStop(0.6, `hsla(${hue}, 50%, 55%, ${alpha * 0.3})`);
      gradient.addColorStop(1, `hsla(${hue}, 50%, 50%, 0)`);
      ctx.fillStyle = gradient;
      ctx.beginPath();
      ctx.arc(nx, ny, r, 0, Math.PI * 2);
      ctx.fill();

      // Faint connecting lines between nearby ambient dots
      if (i > 0) {
        const px = w * (0.1 + 0.8 * (((i - 1) * 2654435761 % 10000) / 10000));
        const py = h * (0.1 + 0.8 * (((i - 1) * 340573321 % 10000) / 10000));
        const pnx = px + noise3D((i - 1) * 0.5, 0, t * 0.15) * 40;
        const pny = py + noise3D(0, (i - 1) * 0.5, t * 0.15) * 40;
        const dist = Math.hypot(nx - pnx, ny - pny);
        if (dist < Math.min(w, h) * 0.4) {
          ctx.strokeStyle = `hsla(${hue}, 40%, 55%, ${0.04 * (1 - dist / (Math.min(w, h) * 0.4))})`;
          ctx.lineWidth = 0.5;
          ctx.beginPath();
          ctx.moveTo(nx, ny);
          ctx.lineTo(pnx, pny);
          ctx.stroke();
        }
      }
    }
    ctx.globalCompositeOperation = 'source-over';
  }
}

// ---------- Waveform ----------

class WaveformRenderer extends BaseRenderer {
  draw(elapsed, dt) {
    const { ctx, w, h } = this;
    this.smoothStep(dt);

    ctx.clearRect(0, 0, w, h);
    const t = elapsed * 0.001;
    const sensors = [...this.sensorState.values()];

    if (sensors.length === 0) {
      this._drawAmbient(t);
      return;
    }

    ctx.globalCompositeOperation = 'lighter';
    const count = sensors.length;

    for (let si = 0; si < count; si++) {
      const s = sensors[si];
      const centerY = h * (0.35 + 0.3 * (si / Math.max(1, count - 1)));
      const freq = 0.0008 + (s.hue / 360) * 0.003;
      const amplitude = (20 + s.intensity * (h * 0.3));
      const phase = t * (1.5 + si * 0.3) + s.hue;
      const alpha = 0.15 + s.intensity * 0.45;

      ctx.strokeStyle = `hsla(${s.hue}, 70%, 60%, ${alpha})`;
      ctx.lineWidth = 1.5 + s.intensity * 1.5;
      ctx.shadowColor = `hsla(${s.hue}, 80%, 60%, ${alpha * 0.5})`;
      ctx.shadowBlur = 8;

      ctx.beginPath();
      for (let x = 0; x <= w; x += 3) {
        const y = centerY + amplitude * Math.sin(x * freq + phase) +
                  amplitude * 0.3 * Math.sin(x * freq * 2.3 + phase * 1.5);
        if (x === 0) ctx.moveTo(x, y);
        else ctx.lineTo(x, y);
      }
      ctx.stroke();
    }

    ctx.shadowBlur = 0;
    ctx.globalCompositeOperation = 'source-over';
  }

  _drawAmbient(t) {
    const { ctx, w, h } = this;
    ctx.globalCompositeOperation = 'lighter';

    for (let i = 0; i < 5; i++) {
      const centerY = h * (0.35 + 0.3 * (i / 4));
      const hue = (i * 72 + 200) % 360;
      const freq = 0.0008 + i * 0.0006;
      const amplitude = 40 + Math.sin(t * 0.3 + i) * 25;
      const alpha = 0.08 + Math.sin(t * 0.4 + i * 1.5) * 0.03;
      ctx.strokeStyle = `hsla(${hue}, 55%, 58%, ${alpha})`;
      ctx.lineWidth = 1.5;
      ctx.shadowColor = `hsla(${hue}, 60%, 55%, ${alpha * 0.4})`;
      ctx.shadowBlur = 6;
      ctx.beginPath();
      for (let x = 0; x <= w; x += 3) {
        const y = centerY + amplitude * Math.sin(x * freq + t * 0.5 + i * 2) +
                  amplitude * 0.2 * Math.sin(x * freq * 2.5 + t * 0.8 + i);
        if (x === 0) ctx.moveTo(x, y);
        else ctx.lineTo(x, y);
      }
      ctx.stroke();
    }
    ctx.shadowBlur = 0;
    ctx.globalCompositeOperation = 'source-over';
  }
}

// ---------- Aurora ----------

class AuroraRenderer extends BaseRenderer {
  draw(elapsed, dt) {
    const { ctx, w, h, noise3D } = this;
    this.smoothStep(dt);

    ctx.clearRect(0, 0, w, h);
    const t = elapsed * 0.001;
    const sensors = [...this.sensorState.values()];

    if (sensors.length === 0) {
      this._drawAmbient(t);
      return;
    }

    ctx.globalCompositeOperation = 'screen';

    for (const s of sensors) {
      const bandY = (s.pos.y / h) * h;
      const bandHeight = 60 + s.intensity * 100;
      const alpha = 0.04 + s.intensity * 0.12;

      // Draw band as a series of horizontal slices for organic shape
      for (let x = 0; x < w; x += 4) {
        const noiseVal = noise3D(x * 0.002, s.hue * 0.01, t * 0.2);
        const yOffset = noiseVal * 50;
        const widthMod = 0.7 + noise3D(x * 0.003, s.hue * 0.02, t * 0.15) * 0.3;
        const localH = bandHeight * widthMod;
        const y = bandY + yOffset - localH / 2;

        const gradient = ctx.createLinearGradient(x, y, x, y + localH);
        gradient.addColorStop(0, `hsla(${s.hue}, 70%, 55%, 0)`);
        gradient.addColorStop(0.3, `hsla(${s.hue}, 70%, 60%, ${alpha})`);
        gradient.addColorStop(0.5, `hsla(${s.hue}, 80%, 65%, ${alpha * 1.2})`);
        gradient.addColorStop(0.7, `hsla(${s.hue}, 70%, 60%, ${alpha})`);
        gradient.addColorStop(1, `hsla(${s.hue}, 70%, 55%, 0)`);

        ctx.fillStyle = gradient;
        ctx.fillRect(x, y, 5, localH);
      }
    }

    ctx.globalCompositeOperation = 'source-over';
  }

  _drawAmbient(t) {
    const { ctx, w, h, noise3D } = this;
    ctx.globalCompositeOperation = 'screen';

    const hues = [190, 240, 290, 340];
    for (let bi = 0; bi < 4; bi++) {
      const bandY = h * (0.2 + bi * 0.18);
      const bandHeight = 100 + Math.sin(t * 0.2 + bi) * 20;
      const alpha = 0.05 + Math.sin(t * 0.3 + bi * 2) * 0.02;

      for (let x = 0; x < w; x += 4) {
        const noiseVal = noise3D(x * 0.002, bi * 0.5, t * 0.12);
        const yOffset = noiseVal * 50;
        const widthMod = 0.7 + noise3D(x * 0.003, bi * 0.3, t * 0.08) * 0.3;
        const localH = bandHeight * widthMod;
        const y = bandY + yOffset - localH / 2;

        const gradient = ctx.createLinearGradient(x, y, x, y + localH);
        gradient.addColorStop(0, `hsla(${hues[bi]}, 55%, 55%, 0)`);
        gradient.addColorStop(0.3, `hsla(${hues[bi]}, 55%, 58%, ${alpha})`);
        gradient.addColorStop(0.5, `hsla(${hues[bi]}, 60%, 62%, ${alpha * 1.2})`);
        gradient.addColorStop(0.7, `hsla(${hues[bi]}, 55%, 58%, ${alpha})`);
        gradient.addColorStop(1, `hsla(${hues[bi]}, 55%, 55%, 0)`);

        ctx.fillStyle = gradient;
        ctx.fillRect(x, y, 5, localH);
      }
    }
    ctx.globalCompositeOperation = 'source-over';
  }
}

// ---------- Particles ----------

const MAX_PARTICLES = 500;

class ParticlesRenderer extends BaseRenderer {
  constructor(canvas, ctx) {
    super(canvas, ctx);
    this.particles = [];
    this.spawnAccum = new Map();
  }

  draw(elapsed, dt) {
    const { ctx, w, h, noise3D } = this;
    this.smoothStep(dt);

    ctx.clearRect(0, 0, w, h);
    const t = elapsed * 0.001;
    const sensors = [...this.sensorState.values()];

    // Spawn particles
    if (sensors.length === 0) {
      this._spawnAmbient(t, dt);
    } else {
      for (const s of sensors) {
        const rate = 0.5 + s.intensity * 4; // particles per second
        const acc = (this.spawnAccum.get(s.id) || 0) + rate * dt;
        const count = Math.floor(acc);
        this.spawnAccum.set(s.id, acc - count);

        for (let i = 0; i < count && this.particles.length < MAX_PARTICLES; i++) {
          this.particles.push({
            x: s.pos.x + (Math.random() - 0.5) * 20,
            y: s.pos.y + (Math.random() - 0.5) * 20,
            vx: (Math.random() - 0.5) * 30,
            vy: (Math.random() - 0.5) * 30,
            age: 0,
            maxAge: 2 + Math.random() * 3,
            hue: s.hue + (Math.random() - 0.5) * 30,
            size: 1.5 + s.intensity * 2 + Math.random(),
          });
        }
      }
    }

    // Update & draw particles
    ctx.globalCompositeOperation = 'lighter';
    for (let i = this.particles.length - 1; i >= 0; i--) {
      const p = this.particles[i];
      p.age += dt;
      if (p.age > p.maxAge) {
        this.particles.splice(i, 1);
        continue;
      }

      // Noise-based drift
      const nx = noise3D(p.x * 0.005, p.y * 0.005, t * 0.3) * 40;
      const ny = noise3D(p.y * 0.005, p.x * 0.005, t * 0.3) * 40;
      p.x += (p.vx + nx) * dt;
      p.y += (p.vy + ny) * dt;

      // Dampen velocity
      p.vx *= 0.98;
      p.vy *= 0.98;

      const life = 1 - p.age / p.maxAge;
      const alpha = life * 0.7;
      const glowR = p.size * 5;

      // Outer glow
      const gradient = ctx.createRadialGradient(p.x, p.y, 0, p.x, p.y, glowR);
      gradient.addColorStop(0, `hsla(${p.hue}, 75%, 70%, ${alpha})`);
      gradient.addColorStop(0.3, `hsla(${p.hue}, 70%, 60%, ${alpha * 0.4})`);
      gradient.addColorStop(1, `hsla(${p.hue}, 70%, 55%, 0)`);
      ctx.fillStyle = gradient;
      ctx.beginPath();
      ctx.arc(p.x, p.y, glowR, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalCompositeOperation = 'source-over';
  }

  _spawnAmbient(t, dt) {
    const acc = (this._ambientAccum || 0) + 8 * dt;
    const count = Math.floor(acc);
    this._ambientAccum = acc - count;
    for (let i = 0; i < count && this.particles.length < MAX_PARTICLES; i++) {
      this.particles.push({
        x: Math.random() * this.w,
        y: Math.random() * this.h,
        vx: (Math.random() - 0.5) * 15,
        vy: (Math.random() - 0.5) * 15,
        age: 0,
        maxAge: 3 + Math.random() * 4,
        hue: (Math.random() * 80 + 190) % 360,
        size: 2.5 + Math.random() * 3,
      });
    }
  }

  dispose() {
    this.particles.length = 0;
    this.spawnAccum.clear();
  }
}

// ---------- Theme Registry ----------

const THEMES = {
  constellation: ConstellationRenderer,
  waveform: WaveformRenderer,
  aurora: AuroraRenderer,
  particles: ParticlesRenderer,
};

// ---------- Hook ----------

const SensorBackgroundHook = {
  mounted() {
    this.canvas = this.el.querySelector('canvas');
    this.ctx = this.canvas.getContext('2d');
    this.theme = 'aurora';
    this.renderer = new THEMES[this.theme](this.canvas, this.ctx);
    this.rafId = null;
    this.lastTime = performance.now();

    this._resizeHandler = () => this._resize();
    window.addEventListener('resize', this._resizeHandler);
    this._resize();

    this.handleEvent('sensor_bg_update', ({ sensors }) => {
      this.renderer.updateSensors(sensors || []);
    });

    this.handleEvent('sensor_bg_theme_change', ({ theme }) => {
      if (THEMES[theme] && theme !== this.theme) {
        this._switchTheme(theme);
      }
    });

    this._startLoop();
  },

  destroyed() {
    if (this.rafId) cancelAnimationFrame(this.rafId);
    window.removeEventListener('resize', this._resizeHandler);
    if (this.renderer.dispose) this.renderer.dispose();
  },

  _resize() {
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    const w = window.innerWidth;
    const h = window.innerHeight;
    this.canvas.width = w * dpr;
    this.canvas.height = h * dpr;
    this.canvas.style.width = w + 'px';
    this.canvas.style.height = h + 'px';
    this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    this.renderer.resize(w, h);
  },

  _switchTheme(theme) {
    const sensors = this.renderer.sensors;
    if (this.renderer.dispose) this.renderer.dispose();
    this.theme = theme;
    this.renderer = new THEMES[theme](this.canvas, this.ctx);
    this._resize();
    this.renderer.updateSensors(sensors);
  },

  _startLoop() {
    const loop = (now) => {
      const dt = Math.min((now - this.lastTime) / 1000, 0.1); // cap at 100ms
      this.lastTime = now;
      this.renderer.draw(now, dt);
      this.rafId = requestAnimationFrame(loop);
    };
    this.rafId = requestAnimationFrame(loop);
  },
};

export { SensorBackgroundHook };
