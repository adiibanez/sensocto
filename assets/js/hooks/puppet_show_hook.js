// Easter Egg — wind-up toy style stick figures going at it.
// Activated by 7 rapid clicks on the octopus logo. Multi-user drag via PubSub.

const BODY_SCALE = 1.8;
const HIT_RADIUS = 70;
const HEART_LIFETIME = 80;
const THRUST_SPEED = 6; // rad/s

function lerp(a, b, t) { return a + (b - a) * t; }
function dist(a, b) { return Math.hypot(a.x - b.x, a.y - b.y); }

// --- Stick figure drawing ---

function drawHead(ctx, x, y, r, skinColor, hairColor, hairStyle) {
  // Hair behind head
  if (hairStyle === 'long') {
    ctx.beginPath();
    ctx.ellipse(x, y + r * 0.3, r * 1.1, r * 1.6, 0, 0, Math.PI * 2);
    ctx.fillStyle = hairColor;
    ctx.fill();
  }
  // Head
  ctx.beginPath();
  ctx.arc(x, y, r, 0, Math.PI * 2);
  ctx.fillStyle = skinColor;
  ctx.fill();
  ctx.strokeStyle = '#333';
  ctx.lineWidth = 2;
  ctx.stroke();
  // Hair on top
  if (hairStyle === 'short') {
    ctx.beginPath();
    ctx.arc(x, y - r * 0.15, r * 1.05, Math.PI * 1.1, Math.PI * 1.9);
    ctx.fillStyle = hairColor;
    ctx.fill();
  }
  // Eyes — little dots
  ctx.fillStyle = '#333';
  ctx.beginPath();
  ctx.arc(x - r * 0.3, y - r * 0.1, r * 0.12, 0, Math.PI * 2);
  ctx.fill();
  ctx.beginPath();
  ctx.arc(x + r * 0.3, y - r * 0.1, r * 0.12, 0, Math.PI * 2);
  ctx.fill();
  // Mouth — open when thrusting
  ctx.beginPath();
  ctx.arc(x, y + r * 0.35, r * 0.2, 0, Math.PI);
  ctx.strokeStyle = '#333';
  ctx.lineWidth = 1.5;
  ctx.stroke();
}

function drawLimb(ctx, x1, y1, x2, y2, thickness, color) {
  ctx.beginPath();
  ctx.moveTo(x1, y1);
  ctx.lineTo(x2, y2);
  ctx.strokeStyle = color;
  ctx.lineWidth = thickness;
  ctx.lineCap = 'round';
  ctx.stroke();
}

function drawBody(ctx, x1, y1, x2, y2, color) {
  ctx.beginPath();
  ctx.moveTo(x1, y1);
  ctx.lineTo(x2, y2);
  ctx.strokeStyle = color;
  ctx.lineWidth = 6 * BODY_SCALE;
  ctx.lineCap = 'round';
  ctx.stroke();
}

// Draw the woman figure (on all fours, facing right)
function drawWoman(ctx, x, y, thrust, time) {
  const s = BODY_SCALE;
  const skin = '#f4c2a1';
  const hair = '#4a2810';
  const limbW = 4 * s;
  const bodyBob = Math.sin(thrust) * 3 * s;
  const headBob = Math.sin(thrust + 0.3) * 4 * s;

  // Torso — horizontal, slightly bobbing
  const torsoLen = 40 * s;
  const hipX = x;
  const hipY = y + bodyBob;
  const shoulderX = x - torsoLen;
  const shoulderY = y - 5 * s + bodyBob * 0.7;

  drawBody(ctx, hipX, hipY, shoulderX, shoulderY, skin);

  // Legs — kneeling
  const kneeX = hipX + 8 * s;
  const kneeY = hipY + 25 * s;
  const footX = hipX - 5 * s;
  const footY = hipY + 40 * s;
  drawLimb(ctx, hipX, hipY, kneeX, kneeY, limbW, skin);
  drawLimb(ctx, kneeX, kneeY, footX, footY, limbW, skin);

  // Other leg
  const kneeX2 = hipX + 12 * s;
  drawLimb(ctx, hipX, hipY, kneeX2, kneeY - 2 * s, limbW, skin);
  drawLimb(ctx, kneeX2, kneeY - 2 * s, footX + 6 * s, footY, limbW, skin);

  // Arms — supporting on ground
  const elbowX = shoulderX - 5 * s;
  const elbowY = shoulderY + 18 * s;
  const handX = shoulderX + 2 * s;
  const handY = shoulderY + 35 * s;
  drawLimb(ctx, shoulderX, shoulderY, elbowX, elbowY, limbW, skin);
  drawLimb(ctx, elbowX, elbowY, handX, handY, limbW, skin);

  const elbowX2 = shoulderX - 10 * s;
  drawLimb(ctx, shoulderX, shoulderY, elbowX2, elbowY + 2 * s, limbW, skin);
  drawLimb(ctx, elbowX2, elbowY + 2 * s, handX - 5 * s, handY, limbW, skin);

  // Butt — round
  ctx.beginPath();
  ctx.arc(hipX + 2 * s, hipY - 2 * s, 12 * s, 0, Math.PI * 2);
  ctx.fillStyle = skin;
  ctx.fill();
  ctx.strokeStyle = '#e0a882';
  ctx.lineWidth = 1.5;
  ctx.stroke();

  // Breasts (small circles hanging down)
  const boobY = shoulderY + 8 * s + Math.abs(bodyBob) * 0.5;
  ctx.beginPath();
  ctx.arc(shoulderX + 5 * s, boobY, 6 * s, 0, Math.PI * 2);
  ctx.fillStyle = skin;
  ctx.fill();
  ctx.strokeStyle = '#e0a882';
  ctx.lineWidth = 1;
  ctx.stroke();

  // Head
  const headX = shoulderX - 12 * s;
  const headY = shoulderY - 8 * s + headBob;
  drawHead(ctx, headX, headY, 10 * s, skin, hair, 'long');

  // Mouth expression — "O" shape when thrust peak
  const mouthOpen = Math.abs(Math.sin(thrust)) * 4 * s;
  if (mouthOpen > 1) {
    ctx.beginPath();
    ctx.ellipse(headX, headY + 10 * s * 0.35, 2.5 * s, mouthOpen * 0.4, 0, 0, Math.PI * 2);
    ctx.fillStyle = '#c44';
    ctx.fill();
  }
}

// Draw the man figure (standing behind, thrusting)
function drawMan(ctx, x, y, thrust, time) {
  const s = BODY_SCALE;
  const skin = '#d4a574';
  const hair = '#2a1a0a';
  const limbW = 4.5 * s;
  const thrustOffset = Math.sin(thrust) * 10 * s;

  // Torso — upright, leaning forward slightly
  const hipX = x + thrustOffset;
  const hipY = y;
  const shoulderX = hipX - 15 * s;
  const shoulderY = hipY - 40 * s;

  drawBody(ctx, hipX, hipY, shoulderX, shoulderY, skin);

  // Legs — standing
  const kneeX = hipX + 5 * s;
  const kneeY = hipY + 22 * s;
  const footX = hipX - 2 * s;
  const footY = hipY + 42 * s;
  drawLimb(ctx, hipX, hipY, kneeX, kneeY, limbW, skin);
  drawLimb(ctx, kneeX, kneeY, footX, footY, limbW, skin);

  const kneeX2 = hipX + 10 * s;
  drawLimb(ctx, hipX, hipY, kneeX2, kneeY + 2 * s, limbW, skin);
  drawLimb(ctx, kneeX2, kneeY + 2 * s, footX + 8 * s, footY, limbW, skin);

  // Arms — hands gripping (at woman's hip level)
  const gripX = hipX - 30 * s + thrustOffset * 0.3;
  const gripY = hipY + 2 * s;
  const elbowX = shoulderX + 5 * s;
  const elbowY = shoulderY + 20 * s;
  drawLimb(ctx, shoulderX, shoulderY, elbowX, elbowY, limbW, skin);
  drawLimb(ctx, elbowX, elbowY, gripX, gripY, limbW, skin);

  const elbowX2 = shoulderX + 10 * s;
  drawLimb(ctx, shoulderX, shoulderY, elbowX2, elbowY - 3 * s, limbW, skin);
  drawLimb(ctx, elbowX2, elbowY - 3 * s, gripX + 4 * s, gripY - 2 * s, limbW, skin);

  // Head
  const headBob = Math.sin(thrust - 0.2) * 2 * s;
  const headX = shoulderX - 3 * s;
  const headY = shoulderY - 14 * s + headBob;
  drawHead(ctx, headX, headY, 10 * s, skin, hair, 'short');

  // Grin — wider at thrust peaks
  const grin = Math.abs(Math.sin(thrust)) * 3 * s;
  ctx.beginPath();
  ctx.arc(headX, headY + 10 * s * 0.3, 3 * s + grin * 0.3, 0.1, Math.PI - 0.1);
  ctx.strokeStyle = '#333';
  ctx.lineWidth = 1.5;
  ctx.stroke();
}

// A mini platform/base under the pair (like the wind-up toy base)
function drawBase(ctx, x, y, width) {
  const s = BODY_SCALE;
  const h = 8 * s;
  const w = width;
  const baseY = y + 44 * s;

  // Base platform
  ctx.beginPath();
  ctx.roundRect(x - w / 2, baseY, w, h, 4 * s);
  ctx.fillStyle = '#8B4513';
  ctx.fill();
  ctx.strokeStyle = '#5C2E00';
  ctx.lineWidth = 2;
  ctx.stroke();

  // Wind-up key on the side
  const keyX = x + w / 2 + 4 * s;
  const keyY = baseY + h / 2;
  ctx.beginPath();
  ctx.moveTo(keyX, keyY);
  ctx.lineTo(keyX + 12 * s, keyY);
  ctx.strokeStyle = '#999';
  ctx.lineWidth = 3 * s;
  ctx.lineCap = 'round';
  ctx.stroke();

  // Key handle (T-shape)
  ctx.beginPath();
  ctx.moveTo(keyX + 12 * s, keyY - 6 * s);
  ctx.lineTo(keyX + 12 * s, keyY + 6 * s);
  ctx.strokeStyle = '#999';
  ctx.lineWidth = 3 * s;
  ctx.stroke();
}

function drawHeart(ctx, cx, cy, size, color) {
  ctx.save();
  ctx.translate(cx, cy);
  ctx.scale(size / 10, size / 10);
  ctx.beginPath();
  ctx.moveTo(0, 3);
  ctx.bezierCurveTo(-5, -2, -10, 2, 0, 10);
  ctx.moveTo(0, 3);
  ctx.bezierCurveTo(5, -2, 10, 2, 0, 10);
  ctx.fillStyle = color;
  ctx.fill();
  ctx.restore();
}

class HeartParticle {
  constructor(x, y) {
    this.x = x;
    this.y = y;
    this.vx = (Math.random() - 0.5) * 2;
    this.vy = -Math.random() * 2.5 - 0.5;
    this.life = HEART_LIFETIME;
    this.size = 5 + Math.random() * 7;
  }

  update() {
    this.x += this.vx;
    this.y += this.vy;
    this.vy *= 0.98;
    this.vx *= 0.98;
    this.life--;
    return this.life > 0;
  }

  draw(ctx) {
    const alpha = this.life / HEART_LIFETIME;
    ctx.save();
    ctx.globalAlpha = alpha;
    drawHeart(ctx, this.x, this.y, this.size * (0.5 + (1 - alpha) * 0.5), '#ff4466');
    ctx.restore();
  }
}

// Simple pair wrapper for hit-testing and dragging
class FigurePair {
  constructor(x, y) {
    this.x = x;
    this.y = y;
    this.targetX = x;
    this.targetY = y;
    this.grabbed = false;
  }

  update() {
    if (!this.grabbed) {
      this.x = lerp(this.x, this.targetX, 0.06);
      this.y = lerp(this.y, this.targetY, 0.06);
    }
  }

  hitTest(px, py) {
    return Math.abs(px - this.x) < HIT_RADIUS * 2 && Math.abs(py - this.y) < HIT_RADIUS;
  }
}

export const PuppetShowHook = {
  mounted() {
    this._active = false;
    this._raf = null;
    this._hearts = [];
    this._dragging = null;
    this._lastBroadcast = 0;
    this._thrustPhase = 0;

    this._onActivate = () => this.pushEvent("activate_puppets", {});
    window.addEventListener("octopus-easter-egg", this._onActivate);

    this.handleEvent("puppets_activated", () => this.show());
    this.handleEvent("puppet_moved", (data) => this.onRemoteMove(data));
    this.handleEvent("puppets_dismissed", () => this.hide());
  },

  show() {
    if (this._active) return;
    this._active = true;

    const overlay = document.createElement('div');
    overlay.id = 'puppet-overlay';
    overlay.style.cssText = 'position:fixed;inset:0;z-index:90;background:rgba(0,0,0,0.75);cursor:default;';

    const canvas = document.createElement('canvas');
    canvas.style.cssText = 'width:100%;height:100%;';
    overlay.appendChild(canvas);

    const closeBtn = document.createElement('button');
    closeBtn.textContent = '\u00d7';
    closeBtn.style.cssText = 'position:absolute;top:16px;right:16px;color:#fff;font-size:32px;background:none;border:none;cursor:pointer;z-index:91;line-height:1;padding:8px;';
    closeBtn.onclick = () => this.pushEvent("dismiss_puppets", {});
    overlay.appendChild(closeBtn);

    document.body.appendChild(overlay);
    this._overlay = overlay;
    this._canvas = canvas;
    this._ctx = canvas.getContext('2d');

    this.resize();
    this._resizeHandler = () => this.resize();
    window.addEventListener('resize', this._resizeHandler);

    const cx = canvas.width / 2;
    const cy = canvas.height / 2;
    this._pair = new FigurePair(cx, cy);

    // Input handlers — drag the whole pair
    this._onMouseMove = (e) => {
      if (this._dragging) {
        this._pair.x = e.clientX;
        this._pair.y = e.clientY;
        this._pair.targetX = e.clientX;
        this._pair.targetY = e.clientY;
        this.throttleBroadcast(0, e.clientX, e.clientY);
      }
    };
    this._onMouseDown = (e) => {
      if (this._pair.hitTest(e.clientX, e.clientY)) {
        this._dragging = true;
        this._pair.grabbed = true;
        canvas.style.cursor = 'grabbing';
      }
    };
    this._onMouseUp = () => {
      if (this._dragging) {
        this._pair.grabbed = false;
        this._dragging = false;
        canvas.style.cursor = 'default';
      }
    };

    this._onTouchStart = (e) => {
      const t = e.touches[0];
      if (this._pair.hitTest(t.clientX, t.clientY)) {
        this._dragging = true;
        this._pair.grabbed = true;
        e.preventDefault();
      }
    };
    this._onTouchMove = (e) => {
      if (this._dragging) {
        const t = e.touches[0];
        this._pair.x = t.clientX;
        this._pair.y = t.clientY;
        this._pair.targetX = t.clientX;
        this._pair.targetY = t.clientY;
        this.throttleBroadcast(0, t.clientX, t.clientY);
        e.preventDefault();
      }
    };
    this._onTouchEnd = () => {
      if (this._dragging) {
        this._pair.grabbed = false;
        this._dragging = false;
      }
    };

    overlay.addEventListener('mousemove', this._onMouseMove);
    overlay.addEventListener('mousedown', this._onMouseDown);
    overlay.addEventListener('mouseup', this._onMouseUp);
    overlay.addEventListener('touchstart', this._onTouchStart, { passive: false });
    overlay.addEventListener('touchmove', this._onTouchMove, { passive: false });
    overlay.addEventListener('touchend', this._onTouchEnd);

    this.playActivationSound();
    this.animate(0);
  },

  resize() {
    if (!this._canvas) return;
    this._canvas.width = window.innerWidth;
    this._canvas.height = window.innerHeight;
  },

  animate(t) {
    if (!this._active) return;

    try {
      const ctx = this._ctx;
      const canvas = this._canvas;
      const time = t / 1000;

      ctx.clearRect(0, 0, canvas.width, canvas.height);

      this._thrustPhase += 0.12;
      const thrust = this._thrustPhase * THRUST_SPEED;

      this._pair.update();
      const px = this._pair.x;
      const py = this._pair.y;

      // Draw wind-up toy base
      drawBase(ctx, px - 10 * BODY_SCALE, py, 120 * BODY_SCALE);

      // Draw woman (in front, on all fours)
      ctx.save();
      drawWoman(ctx, px - 30 * BODY_SCALE, py, thrust, time);
      ctx.restore();

      // Draw man (behind, thrusting)
      ctx.save();
      drawMan(ctx, px + 15 * BODY_SCALE, py, thrust, time);
      ctx.restore();

      // Heart particles — burst from between them
      if (Math.random() < 0.12) {
        this._hearts.push(new HeartParticle(
          px - 5 * BODY_SCALE + (Math.random() - 0.5) * 30,
          py - 20 * BODY_SCALE
        ));
      }

      for (let i = this._hearts.length - 1; i >= 0; i--) {
        if (!this._hearts[i].update()) {
          this._hearts.splice(i, 1);
        } else {
          this._hearts[i].draw(ctx);
        }
      }

      // Cheeky caption
      ctx.save();
      ctx.font = `${12 * BODY_SCALE}px monospace`;
      ctx.fillStyle = '#ff6b9d';
      ctx.textAlign = 'center';
      ctx.globalAlpha = 0.7;
      const quips = [
        'wind me up baby',
        'made in china',
        'batteries not included',
        'ages 18+',
        'not a children\'s toy',
        'collector\'s edition',
      ];
      const idx = Math.floor(time / 5) % quips.length;
      ctx.fillText(quips[idx], px - 10 * BODY_SCALE, py + 62 * BODY_SCALE);
      ctx.restore();

      // Squeak sound indicators — little "!" at thrust peaks
      const thrustAbs = Math.abs(Math.sin(thrust));
      if (thrustAbs > 0.95) {
        ctx.save();
        ctx.font = `bold ${16 * BODY_SCALE}px sans-serif`;
        ctx.fillStyle = '#ffcc00';
        ctx.textAlign = 'center';
        const exX = px - 65 * BODY_SCALE + (Math.random() - 0.5) * 10;
        const exY = py - 35 * BODY_SCALE + (Math.random() - 0.5) * 10;
        ctx.fillText('!', exX, exY);
        ctx.restore();
      }
    } catch (e) { /* swallow — keep RAF alive */ }

    this._raf = requestAnimationFrame((t2) => this.animate(t2));
  },

  throttleBroadcast(puppetIdx, x, y) {
    const now = Date.now();
    if (now - this._lastBroadcast < 66) return;
    this._lastBroadcast = now;
    this.pushEvent("puppet_move", {
      puppet: puppetIdx,
      x: Math.round(x),
      y: Math.round(y)
    });
  },

  onRemoteMove({ puppet, x, y }) {
    if (!this._pair) return;
    if (this._pair.grabbed) return;
    this._pair.targetX = x;
    this._pair.targetY = y;
  },

  hide() {
    this._active = false;
    if (this._raf) cancelAnimationFrame(this._raf);
    if (this._overlay) {
      this._overlay.remove();
      this._overlay = null;
    }
    if (this._resizeHandler) {
      window.removeEventListener('resize', this._resizeHandler);
    }
    this._hearts = [];
    this._pair = null;
  },

  playActivationSound() {
    try {
      const ctx = new (window.AudioContext || window.webkitAudioContext)();
      const now = ctx.currentTime;

      // Cheesy "bow chicka wow wow"
      const notes = [196, 247, 220, 330]; // G3 B3 A3 E4
      notes.forEach((freq, i) => {
        const osc = ctx.createOscillator();
        const gain = ctx.createGain();
        osc.connect(gain);
        gain.connect(ctx.destination);
        osc.type = i < 2 ? 'sawtooth' : 'triangle';
        osc.frequency.setValueAtTime(freq, now + i * 0.18);
        gain.gain.setValueAtTime(0, now + i * 0.18);
        gain.gain.linearRampToValueAtTime(0.12, now + i * 0.18 + 0.03);
        gain.gain.exponentialRampToValueAtTime(0.001, now + i * 0.18 + 0.35);
        osc.start(now + i * 0.18);
        osc.stop(now + i * 0.18 + 0.4);
      });

      // Wah-wah slide
      const wahOsc = ctx.createOscillator();
      const wahGain = ctx.createGain();
      wahOsc.connect(wahGain);
      wahGain.connect(ctx.destination);
      wahOsc.type = 'sine';
      wahOsc.frequency.setValueAtTime(300, now + 0.75);
      wahOsc.frequency.exponentialRampToValueAtTime(150, now + 1.1);
      wahOsc.frequency.exponentialRampToValueAtTime(300, now + 1.3);
      wahGain.gain.setValueAtTime(0, now + 0.75);
      wahGain.gain.linearRampToValueAtTime(0.15, now + 0.78);
      wahGain.gain.exponentialRampToValueAtTime(0.001, now + 1.4);
      wahOsc.start(now + 0.75);
      wahOsc.stop(now + 1.5);
    } catch (e) { /* no audio, no problem */ }
  },

  destroyed() {
    this.hide();
    window.removeEventListener("octopus-easter-egg", this._onActivate);
  }
};

export const OctopusLogoHook = {
  mounted() {
    this._clicks = 0;
    this._timer = null;

    const link = this.el.querySelector('a');
    if (!link) return;

    // Strip LiveView's navigation handler so we fully control click behavior.
    // phx-update="ignore" ensures LV won't re-add these attributes.
    link.removeAttribute('data-phx-link');
    link.removeAttribute('data-phx-link-state');

    link.addEventListener('click', (e) => {
      e.preventDefault();

      // On non-lobby pages, just navigate home normally
      if (!window.location.pathname.startsWith('/lobby')) {
        window.location.href = link.getAttribute('href') || '/';
        return;
      }

      this._clicks++;
      clearTimeout(this._timer);

      if (this._clicks >= 7) {
        this._clicks = 0;
        window.dispatchEvent(new CustomEvent("octopus-easter-egg"));
        return;
      }

      // After 800ms idle, navigate home and reset
      this._timer = setTimeout(() => {
        this._clicks = 0;
        window.location.href = link.getAttribute('href') || '/';
      }, 800);
    });
  }
};
