<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import * as THREE from "three";
  import { OrbitControls } from "three/addons/controls/OrbitControls.js";

  let { sensors = [] }: {
    sensors: Array<{ sensor_id: string; orientation: any }>;
  } = $props();

  let canvas2d: HTMLCanvasElement;
  let container3d: HTMLDivElement;
  let ctx: CanvasRenderingContext2D | null = null;
  let rafId: number = 0;
  let cssW = 0;
  let cssH = 0;

  // ── Visualization mode ────────────────────────────────────────────
  type VizMode = 'field' | 'waves' | 'radial' | 'cubes';
  let mode: VizMode = $state('waves');
  let prevMode: VizMode = 'waves';

  // ── Timeline window (seconds shown in waves view) ──────────────────
  const TIME_WINDOWS = [2, 4, 8] as const;
  let timeWindow: number = $state(8);

  // ── Three.js state ────────────────────────────────────────────────
  let threeScene: THREE.Scene | null = null;
  let threeCamera: THREE.PerspectiveCamera | null = null;
  let threeRenderer: THREE.WebGLRenderer | null = null;
  let threeControls: OrbitControls | null = null;
  let threeRaycaster = new THREE.Raycaster();
  let threeMouse = new THREE.Vector2();
  let threeCubes: Map<string, { mesh: THREE.Mesh; label: THREE.Sprite; trail: THREE.Line }> = new Map();
  let threeInitialized = false;
  let focusedSensorId: string | null = null;
  let focusTarget = new THREE.Vector3();
  let focusCamTarget = new THREE.Vector3();

  // ── Shared sensor state ───────────────────────────────────────────
  interface SensorState {
    id: string;
    label: string;
    cx: number; cy: number;
    // Current smoothed values (used for field/radial/cubes viz + wave writes)
    x: number; y: number; z: number;
    // Raw target values — set directly on data arrival, smoothed toward per-frame
    rawX: number; rawY: number; rawZ: number;
    // Velocity from integrating acceleration (for cubes mode)
    vx: number; vy: number; vz: number;
    // Displacement from integrating velocity
    px: number; py: number; pz: number;
    mag: number;
    peak: number;
    trail: Array<{ x: number; y: number; mag: number }>;
    waveX: Float32Array; waveY: Float32Array; waveZ: Float32Array;
    waveHead: number;
    waveLastWriteTime: number;
    hue: number;
    lastUpdate: number;
  }

  const sensorMap: Map<string, SensorState> = new Map();
  let sensorList: SensorState[] = [];
  const TRAIL_LEN = 40;
  const WAVE_LEN = 512;
  // Per-frame interpolation speed toward raw target (0→1). Higher = more responsive.
  // At 60fps, 0.35 gives ~95% convergence in ~8 frames (~133ms) — smooth but responsive.
  const FRAME_SMOOTHING = 0.35;
  const MAG_SMOOTHING = 0.15;
  const PEAK_DECAY = 0.93;
  const STALE_MS = 3000;
  const WAVE_SAMPLES_PER_SEC = 60;

  const IMU_ATTRS = new Set([
    'imu', 'accelerometer', 'accelerometer_x', 'accelerometer_y', 'accelerometer_z',
    'gyroscope', 'gyroscope_x', 'gyroscope_y', 'gyroscope_z', 'motion'
  ]);

  let nextHueIndex = 0;
  function nextHue(): number {
    const h = (nextHueIndex * 137.508) % 360;
    nextHueIndex++;
    return h;
  }

  function getOrCreateSensor(id: string): SensorState {
    let s = sensorMap.get(id);
    if (!s) {
      s = {
        id, label: shortLabel(id),
        cx: 0, cy: 0,
        x: 0, y: 0, z: 0,
        rawX: 0, rawY: 0, rawZ: 0,
        vx: 0, vy: 0, vz: 0,
        px: 0, py: 0, pz: 0,
        mag: 0, peak: 0,
        trail: [],
        waveX: new Float32Array(WAVE_LEN),
        waveY: new Float32Array(WAVE_LEN),
        waveZ: new Float32Array(WAVE_LEN),
        waveHead: 0,
        waveLastWriteTime: 0,
        hue: nextHue(),
        lastUpdate: Date.now(),
      };
      sensorMap.set(id, s);
      sensorList = Array.from(sensorMap.values());
      layoutSensors();
    }
    return s;
  }

  function shortLabel(id: string): string {
    const parts = id.split('_');
    if (parts.length >= 2) {
      const last = parts[parts.length - 1];
      const prev = parts[parts.length - 2];
      return `${prev.charAt(0).toUpperCase()}${prev.slice(1)} ${last}`;
    }
    return id.length > 10 ? '…' + id.slice(-8) : id;
  }

  function layoutSensors() {
    const n = sensorList.length;
    if (n === 0) return;
    if (n === 1) { sensorList[0].cx = 0.5; sensorList[0].cy = 0.5; return; }
    const rings = Math.ceil(Math.sqrt(n));
    let idx = 0;
    for (let ring = 0; ring < rings && idx < n; ring++) {
      const count = ring === 0 ? 1 : Math.min(ring * 6, n - idx);
      const radius = ring === 0 ? 0 : (0.15 + ring * 0.18);
      for (let i = 0; i < count && idx < n; i++) {
        const angle = (i / count) * Math.PI * 2 - Math.PI / 2 + ring * 0.3;
        sensorList[idx].cx = 0.5 + Math.cos(angle) * radius;
        sensorList[idx].cy = 0.5 + Math.sin(angle) * radius;
        idx++;
      }
    }
  }

  // ── Data ingestion ────────────────────────────────────────────────
  // Sets raw target values. Smoothing + wave writes happen per-frame in
  // advanceWaveBuffers(), completely decoupled from network arrival timing.
  function ingestMeasurement(sensorId: string, attributeId: string, payload: any) {
    const s = getOrCreateSensor(sensorId);
    s.lastUpdate = Date.now();

    if (typeof payload === 'number') {
      if (attributeId.endsWith('_x')) s.rawX = payload;
      else if (attributeId.endsWith('_y')) s.rawY = payload;
      else if (attributeId.endsWith('_z')) s.rawZ = payload;
      else if (attributeId.startsWith('accel')) s.rawX = payload;
      else if (attributeId.startsWith('gyro')) s.rawY = payload;
      else if (attributeId === 'motion') s.rawZ = payload;
      else s.rawX = payload;
    } else if (typeof payload === 'string' && payload.includes(',')) {
      // Fallback: parse bundled IMU CSV payload (timestamp,ax,ay,az,rx,ry,rz,...)
      const parts = payload.split(',').map(Number);
      if (parts.length >= 7) {
        s.rawX = parts[1] || 0; // ax
        s.rawY = parts[2] || 0; // ay
        s.rawZ = parts[3] || 0; // az
      } else if (parts.length >= 3) {
        s.rawX = parts[0] || 0;
        s.rawY = parts[1] || 0;
        s.rawZ = parts[2] || 0;
      }
    } else if (payload && typeof payload === 'object') {
      // Unified IMU format: {accelerometer: {x,y,z}, gyroscope: {x,y,z}}
      if (payload.accelerometer) {
        s.rawX = payload.accelerometer.x || 0;
        s.rawY = payload.accelerometer.y || 0;
        s.rawZ = payload.accelerometer.z || 0;
      } else if ('x' in payload) {
        s.rawX = payload.x;
        if ('y' in payload) s.rawY = payload.y;
        if ('z' in payload) s.rawZ = payload.z;
      }
    }
  }

  // Called once per render frame. Smoothly interpolates x/y/z toward raw targets,
  // then writes the interpolated values into wave buffers at a constant rate.
  // This produces smooth, continuous waveforms regardless of bursty data arrival.
  function advanceWaveBuffers(now: number) {
    const msPerSample = 1000 / WAVE_SAMPLES_PER_SEC;

    for (const s of sensorList) {
      // Per-frame interpolation: x/y/z chase rawX/rawY/rawZ smoothly
      s.x += (s.rawX - s.x) * FRAME_SMOOTHING;
      s.y += (s.rawY - s.y) * FRAME_SMOOTHING;
      s.z += (s.rawZ - s.z) * FRAME_SMOOTHING;

      // Update magnitude
      const rawMag = Math.sqrt(s.x * s.x + s.y * s.y + s.z * s.z);
      const prevMag = s.mag;
      s.mag += (rawMag - s.mag) * MAG_SMOOTHING;
      if (rawMag > prevMag * 1.3 && rawMag > 0.3) {
        s.peak = Math.min(1.0, rawMag / 3);
      }

      // Time-driven wave write
      if (s.waveLastWriteTime === 0) { s.waveLastWriteTime = now; continue; }
      const elapsed = now - s.waveLastWriteTime;
      const samplesToWrite = Math.floor(elapsed / msPerSample);
      if (samplesToWrite <= 0) continue;

      const n = Math.min(samplesToWrite, 4);
      for (let i = 0; i < n; i++) {
        const idx = s.waveHead % WAVE_LEN;
        s.waveX[idx] = s.x;
        s.waveY[idx] = s.y;
        s.waveZ[idx] = s.z;
        s.waveHead++;
      }
      s.waveLastWriteTime = now - (elapsed % msPerSample);
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // 2D RENDER MODES
  // ══════════════════════════════════════════════════════════════════

  function renderField(W: number, H: number, now: number) {
    ctx!.fillStyle = 'rgba(10, 8, 20, 0.15)';
    ctx!.fillRect(0, 0, W, H);
    ctx!.strokeStyle = 'rgba(75, 85, 99, 0.06)';
    ctx!.lineWidth = 1;
    for (let x = 40; x < W; x += 40) { ctx!.beginPath(); ctx!.moveTo(x, 0); ctx!.lineTo(x, H); ctx!.stroke(); }
    for (let y = 40; y < H; y += 40) { ctx!.beginPath(); ctx!.moveTo(0, y); ctx!.lineTo(W, y); ctx!.stroke(); }
    const maxOrbit = Math.min(W, H) * 0.2;
    for (const s of sensorList) {
      const stale = now - s.lastUpdate > STALE_MS;
      const a = stale ? 0.2 : 1.0;
      const bx = s.cx * W, by = s.cy * H;
      const ox = Math.tanh(s.x / 2) * maxOrbit, oy = Math.tanh(s.y / 2) * maxOrbit;
      const px = bx + ox, py = by + oy;
      const br = Math.min(W, H) * 0.025;
      const r = br + Math.min(br * 3, s.mag * 8);
      s.trail.push({ x: px, y: py, mag: s.mag });
      if (s.trail.length > TRAIL_LEN) s.trail.shift();
      if (s.trail.length > 2) {
        ctx!.beginPath(); ctx!.moveTo(s.trail[0].x, s.trail[0].y);
        for (let i = 1; i < s.trail.length; i++) ctx!.lineTo(s.trail[i].x, s.trail[i].y);
        ctx!.strokeStyle = `hsla(${s.hue}, 70%, 55%, ${0.4 * a})`;
        ctx!.lineWidth = Math.max(1, r * 0.3); ctx!.lineCap = 'round'; ctx!.lineJoin = 'round'; ctx!.stroke();
        ctx!.strokeStyle = `hsla(${s.hue}, 80%, 60%, ${0.1 * a})`; ctx!.lineWidth = Math.max(2, r * 0.8); ctx!.stroke();
      }
      if (s.peak > 0.05) {
        ctx!.beginPath(); ctx!.arc(px, py, r + s.peak * maxOrbit * 0.8, 0, Math.PI * 2);
        ctx!.strokeStyle = `hsla(${s.hue}, 90%, 70%, ${s.peak * 0.5 * a})`; ctx!.lineWidth = 2; ctx!.stroke();
        s.peak *= PEAK_DECAY;
      }
      const grad = ctx!.createRadialGradient(px, py, 0, px, py, r * 3);
      grad.addColorStop(0, `hsla(${s.hue}, 80%, 65%, ${0.3 * a})`); grad.addColorStop(1, `hsla(${s.hue}, 80%, 65%, 0)`);
      ctx!.fillStyle = grad; ctx!.beginPath(); ctx!.arc(px, py, r * 3, 0, Math.PI * 2); ctx!.fill();
      const absX = Math.abs(s.x), absY = Math.abs(s.y), absZ = Math.abs(s.z);
      const tot = absX + absY + absZ + 0.01;
      ctx!.beginPath(); ctx!.arc(px, py, r, 0, Math.PI * 2);
      ctx!.fillStyle = `rgba(${180+75*(absX/tot)|0},${180+75*(absY/tot)|0},${180+75*(absZ/tot)|0},${0.9*a})`; ctx!.fill();
      ctx!.font = '10px Inter, system-ui, sans-serif'; ctx!.textAlign = 'center';
      ctx!.fillStyle = `rgba(200, 200, 220, ${0.7 * a})`; ctx!.fillText(s.label, bx, by + r * 3 + 14);
    }
  }

  function renderWaves(W: number, H: number, now: number) {
    ctx!.fillStyle = '#0a0814'; ctx!.fillRect(0, 0, W, H);
    const n = sensorList.length;
    if (n === 0) { ctx!.fillStyle='#6b7280'; ctx!.font='12px Inter,system-ui,sans-serif'; ctx!.textAlign='center'; ctx!.fillText('Waiting for IMU data…',W/2,H/2); return; }
    const rowH = Math.min(H / n, 120), labelW = 90, chartW = W - labelW - 16;
    // Draw samples for selected time window, capped by buffer and pixel width
    const windowSamples = timeWindow * WAVE_SAMPLES_PER_SEC;
    const samples = Math.min(windowSamples, WAVE_LEN, Math.floor(chartW));
    for (let i = 0; i < n; i++) {
      const s = sensorList[i]; const stale = now - s.lastUpdate > STALE_MS;
      const y0 = i * rowH, mid = y0 + rowH / 2, amp = rowH * 0.35;
      if (i > 0) { ctx!.strokeStyle='rgba(75,85,99,0.2)'; ctx!.lineWidth=1; ctx!.beginPath(); ctx!.moveTo(0,y0); ctx!.lineTo(W,y0); ctx!.stroke(); }
      ctx!.fillStyle = stale ? 'rgba(107,114,128,0.4)' : `hsla(${s.hue},60%,75%,0.9)`;
      ctx!.font='10px Inter,system-ui,sans-serif'; ctx!.textAlign='left'; ctx!.fillText(s.label, 8, mid-8);
      ctx!.font='9px monospace'; ctx!.fillStyle=stale?'rgba(107,114,128,0.3)':'rgba(156,163,175,0.6)';
      ctx!.fillText(`x:${s.x.toFixed(2)} y:${s.y.toFixed(2)} z:${s.z.toFixed(2)}`, 8, mid+6);
      const barW = Math.min(70, s.mag * 20);
      ctx!.fillStyle=`hsla(${s.hue},70%,50%,${stale?0.15:0.3})`; ctx!.fillRect(8, mid+12, barW, 3);
      const head = s.waveHead;
      // Only draw as many samples as we've actually written
      const available = Math.min(head, samples);
      const channels: [Float32Array, string][] = [
        [s.waveX, `hsla(${s.hue},80%,65%,${stale?0.15:0.85})`],
        [s.waveY, `hsla(${(s.hue+120)%360},70%,60%,${stale?0.1:0.6})`],
        [s.waveZ, `hsla(${(s.hue+240)%360},60%,55%,${stale?0.1:0.4})`],
      ];
      for (const [wave, color] of channels) {
        ctx!.beginPath(); let started = false;
        for (let j = 0; j < available; j++) {
          const idx = ((head - available + j) % WAVE_LEN + WAVE_LEN) % WAVE_LEN;
          const sx = labelW + (j / available) * chartW;
          const sy = mid - Math.tanh(wave[idx] / 3) * amp;
          if (!started) { ctx!.moveTo(sx, sy); started = true; } else ctx!.lineTo(sx, sy);
        }
        ctx!.strokeStyle=color; ctx!.lineWidth=1.5; ctx!.lineCap='round'; ctx!.stroke();
      }
      ctx!.strokeStyle='rgba(75,85,99,0.15)'; ctx!.lineWidth=1; ctx!.setLineDash([4,4]);
      ctx!.beginPath(); ctx!.moveTo(labelW,mid); ctx!.lineTo(W-8,mid); ctx!.stroke(); ctx!.setLineDash([]);
    }
  }

  function renderRadial(W: number, H: number, now: number) {
    ctx!.fillStyle = 'rgba(10, 8, 20, 0.12)'; ctx!.fillRect(0, 0, W, H);
    const cx = W/2, cy = H/2, maxR = Math.min(W,H)*0.42, n = sensorList.length;
    for (let r = 1; r <= 3; r++) { ctx!.beginPath(); ctx!.arc(cx,cy,maxR*r/3,0,Math.PI*2); ctx!.strokeStyle=`rgba(75,85,99,${0.08+r*0.02})`; ctx!.lineWidth=1; ctx!.stroke(); }
    ctx!.beginPath(); ctx!.arc(cx,cy,3,0,Math.PI*2); ctx!.fillStyle='rgba(156,163,175,0.4)'; ctx!.fill();
    if (n === 0) return;
    const sliceAngle = (Math.PI * 2) / Math.max(n, 1);
    for (let i = 0; i < n; i++) {
      const s = sensorList[i]; const stale = now-s.lastUpdate>STALE_MS; const a = stale?0.2:1.0;
      const baseAngle = i*sliceAngle - Math.PI/2;
      const head = s.waveHead, samples = Math.min(WAVE_LEN, 120), angleSpread = sliceAngle * 0.85;
      // X waveform
      ctx!.beginPath(); let started = false;
      for (let j = 0; j < samples; j++) {
        const t=j/samples, angle=baseAngle-angleSpread/2+t*angleSpread;
        const idx=((head-samples+j)%WAVE_LEN+WAVE_LEN)%WAVE_LEN;
        const dist=maxR*0.3+Math.tanh(s.waveX[idx]/2)*maxR*0.4;
        const px=cx+Math.cos(angle)*dist, py=cy+Math.sin(angle)*dist;
        if(!started){ctx!.moveTo(px,py);started=true;}else ctx!.lineTo(px,py);
      }
      ctx!.strokeStyle=`hsla(${s.hue},75%,60%,${0.7*a})`; ctx!.lineWidth=2; ctx!.lineCap='round'; ctx!.stroke();
      // Y waveform
      ctx!.beginPath(); started=false;
      for (let j = 0; j < samples; j++) {
        const t=j/samples, angle=baseAngle-angleSpread/2+t*angleSpread;
        const idx=((head-samples+j)%WAVE_LEN+WAVE_LEN)%WAVE_LEN;
        const dist=maxR*0.3+Math.tanh(s.waveY[idx]/2)*maxR*0.3;
        const px=cx+Math.cos(angle)*dist, py=cy+Math.sin(angle)*dist;
        if(!started){ctx!.moveTo(px,py);started=true;}else ctx!.lineTo(px,py);
      }
      ctx!.strokeStyle=`hsla(${(s.hue+120)%360},60%,55%,${0.4*a})`; ctx!.lineWidth=1; ctx!.stroke();
      // Fill
      ctx!.beginPath();
      for (let j=0;j<samples;j++){const t=j/samples,angle=baseAngle-angleSpread/2+t*angleSpread;const idx=((head-samples+j)%WAVE_LEN+WAVE_LEN)%WAVE_LEN;const dist=maxR*0.3+Math.tanh(s.waveX[idx]/2)*maxR*0.4;if(j===0)ctx!.moveTo(cx+Math.cos(angle)*dist,cy+Math.sin(angle)*dist);else ctx!.lineTo(cx+Math.cos(angle)*dist,cy+Math.sin(angle)*dist);}
      for(let j=samples-1;j>=0;j--){const t=j/samples,angle=baseAngle-angleSpread/2+t*angleSpread;ctx!.lineTo(cx+Math.cos(angle)*maxR*0.3,cy+Math.sin(angle)*maxR*0.3);}
      ctx!.closePath(); ctx!.fillStyle=`hsla(${s.hue},70%,55%,${0.08*a})`; ctx!.fill();
      // Label
      const lx=cx+Math.cos(baseAngle)*(maxR+18), ly=cy+Math.sin(baseAngle)*(maxR+18);
      ctx!.font='10px Inter,system-ui,sans-serif'; ctx!.textAlign='center'; ctx!.textBaseline='middle';
      ctx!.fillStyle=`hsla(${s.hue},50%,70%,${0.8*a})`; ctx!.fillText(s.label,lx,ly);
      // Dot
      const dotDist=maxR*0.3+Math.tanh(s.x/2)*maxR*0.4;
      const dx=cx+Math.cos(baseAngle)*dotDist, dy=cy+Math.sin(baseAngle)*dotDist;
      ctx!.beginPath(); ctx!.arc(dx,dy,3+s.mag*4,0,Math.PI*2); ctx!.fillStyle=`hsla(${s.hue},80%,70%,${0.9*a})`; ctx!.fill();
      if(s.peak>0.05){ctx!.beginPath();ctx!.arc(dx,dy,6+s.peak*30,0,Math.PI*2);ctx!.strokeStyle=`hsla(${s.hue},90%,75%,${s.peak*0.5})`;ctx!.lineWidth=1.5;ctx!.stroke();s.peak*=PEAK_DECAY;}
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // 3D CUBES MODE
  // ══════════════════════════════════════════════════════════════════

  function initThree() {
    if (threeInitialized || !container3d) return;
    const rect = container3d.getBoundingClientRect();
    if (rect.width === 0 || rect.height === 0) return;

    threeScene = new THREE.Scene();
    threeScene.background = new THREE.Color(0x0a0814);
    threeScene.fog = new THREE.FogExp2(0x0a0814, 0.015);

    threeCamera = new THREE.PerspectiveCamera(50, rect.width / rect.height, 0.1, 200);
    threeCamera.position.set(0, 8, 18);
    threeCamera.lookAt(0, 0, 0);

    threeRenderer = new THREE.WebGLRenderer({ antialias: true, alpha: false });
    threeRenderer.setPixelRatio(window.devicePixelRatio);
    threeRenderer.setSize(rect.width, rect.height);
    container3d.appendChild(threeRenderer.domElement);

    // Lighting
    const ambient = new THREE.AmbientLight(0x404060, 0.6);
    threeScene.add(ambient);
    const dirLight = new THREE.DirectionalLight(0xffffff, 0.8);
    dirLight.position.set(5, 10, 7);
    threeScene.add(dirLight);
    const pointLight = new THREE.PointLight(0x8b5cf6, 0.5, 50);
    pointLight.position.set(-5, 5, -5);
    threeScene.add(pointLight);

    // Ground grid
    const gridHelper = new THREE.GridHelper(30, 30, 0x1a1530, 0x1a1530);
    gridHelper.position.y = -2;
    threeScene.add(gridHelper);

    // Global axes at origin for spatial reference
    const axesHelper = new THREE.AxesHelper(2.5);
    axesHelper.position.y = -1.9;
    threeScene.add(axesHelper);

    // OrbitControls for manual camera rotation/zoom
    threeControls = new OrbitControls(threeCamera, threeRenderer.domElement);
    threeControls.enableDamping = true;
    threeControls.dampingFactor = 0.08;
    threeControls.minDistance = 3;
    threeControls.maxDistance = 60;
    threeControls.maxPolarAngle = Math.PI * 0.85;
    threeControls.target.set(0, 0, 0);

    // Click-to-focus: raycast on click
    threeRenderer.domElement.addEventListener('click', onThreeClick);
    // Double-click to reset view
    threeRenderer.domElement.addEventListener('dblclick', onThreeDoubleClick);

    threeInitialized = true;
  }

  function onThreeClick(event: MouseEvent) {
    if (!threeRenderer || !threeCamera || !threeScene) return;
    const rect = threeRenderer.domElement.getBoundingClientRect();
    threeMouse.x = ((event.clientX - rect.left) / rect.width) * 2 - 1;
    threeMouse.y = -((event.clientY - rect.top) / rect.height) * 2 + 1;
    threeRaycaster.setFromCamera(threeMouse, threeCamera);

    const meshes = Array.from(threeCubes.values()).map(c => c.mesh);
    const intersects = threeRaycaster.intersectObjects(meshes);
    if (intersects.length > 0) {
      const hit = intersects[0].object as THREE.Mesh;
      // Find which sensor this mesh belongs to
      for (const [id, entry] of threeCubes) {
        if (entry.mesh === hit) {
          focusedSensorId = focusedSensorId === id ? null : id;
          break;
        }
      }
    } else {
      focusedSensorId = null;
    }
  }

  function onThreeDoubleClick() {
    focusedSensorId = null;
    if (threeControls) {
      threeControls.target.set(0, 0, 0);
    }
  }

  function disposeThree() {
    if (!threeInitialized) return;
    threeCubes.forEach(({ mesh, label, trail }) => {
      threeScene?.remove(mesh);
      threeScene?.remove(label);
      threeScene?.remove(trail);
      mesh.geometry.dispose();
      (mesh.material as THREE.Material).dispose();
      label.material.map?.dispose();
      label.material.dispose();
      trail.geometry.dispose();
      (trail.material as THREE.Material).dispose();
    });
    threeCubes.clear();
    if (threeControls) { threeControls.dispose(); threeControls = null; }
    if (threeRenderer && container3d) {
      threeRenderer.domElement.removeEventListener('click', onThreeClick);
      threeRenderer.domElement.removeEventListener('dblclick', onThreeDoubleClick);
      container3d.removeChild(threeRenderer.domElement);
      threeRenderer.dispose();
    }
    threeRenderer = null;
    threeScene = null;
    threeCamera = null;
    threeInitialized = false;
    focusedSensorId = null;
  }

  function resizeThree() {
    if (!threeRenderer || !threeCamera || !container3d) return;
    const rect = container3d.getBoundingClientRect();
    if (rect.width === 0 || rect.height === 0) return;
    threeCamera.aspect = rect.width / rect.height;
    threeCamera.updateProjectionMatrix();
    threeRenderer.setSize(rect.width, rect.height);
  }

  function getOrCreateCube(s: SensorState): { mesh: THREE.Mesh; label: THREE.Sprite; trail: THREE.Line } {
    let entry = threeCubes.get(s.id);
    if (entry) return entry;

    const hsl = new THREE.Color();
    hsl.setHSL(s.hue / 360, 0.7, 0.55);

    // Semi-transparent cube
    const geo = new THREE.BoxGeometry(1.2, 1.2, 1.2, 2, 2, 2);
    const mat = new THREE.MeshStandardMaterial({
      color: hsl,
      metalness: 0.3,
      roughness: 0.4,
      emissive: hsl,
      emissiveIntensity: 0.15,
      transparent: true,
      opacity: 0.45,
      depthWrite: false,
    });
    const mesh = new THREE.Mesh(geo, mat);

    // Wireframe edges for visibility
    const edges = new THREE.EdgesGeometry(geo);
    const edgeMat = new THREE.LineBasicMaterial({ color: hsl, transparent: true, opacity: 0.6 });
    const wireframe = new THREE.LineSegments(edges, edgeMat);
    mesh.add(wireframe);

    // XYZ axis arrows attached to cube
    const axisLen = 1.2;
    const xArrow = new THREE.ArrowHelper(new THREE.Vector3(1, 0, 0), new THREE.Vector3(0, 0, 0), axisLen, 0xff4444, 0.2, 0.1);
    const yArrow = new THREE.ArrowHelper(new THREE.Vector3(0, 1, 0), new THREE.Vector3(0, 0, 0), axisLen, 0x44ff44, 0.2, 0.1);
    const zArrow = new THREE.ArrowHelper(new THREE.Vector3(0, 0, 1), new THREE.Vector3(0, 0, 0), axisLen, 0x4488ff, 0.2, 0.1);
    mesh.add(xArrow);
    mesh.add(yArrow);
    mesh.add(zArrow);

    // Text label sprite
    const labelCanvas = document.createElement('canvas');
    labelCanvas.width = 256; labelCanvas.height = 64;
    const lctx = labelCanvas.getContext('2d')!;
    lctx.fillStyle = 'rgba(0,0,0,0)';
    lctx.fillRect(0, 0, 256, 64);
    lctx.font = '24px Inter, system-ui, sans-serif';
    lctx.textAlign = 'center';
    lctx.fillStyle = '#c4b5fd';
    lctx.fillText(s.label, 128, 40);
    const labelTexture = new THREE.CanvasTexture(labelCanvas);
    const labelMat = new THREE.SpriteMaterial({ map: labelTexture, transparent: true, opacity: 0.8 });
    const label = new THREE.Sprite(labelMat);
    label.scale.set(3, 0.75, 1);

    // Motion trail line
    const trailGeo = new THREE.BufferGeometry();
    const trailPositions = new Float32Array(TRAIL_LEN * 3);
    trailGeo.setAttribute('position', new THREE.BufferAttribute(trailPositions, 3));
    const trailMat = new THREE.LineBasicMaterial({ color: hsl, transparent: true, opacity: 0.3 });
    const trail = new THREE.Line(trailGeo, trailMat);

    threeScene!.add(mesh);
    threeScene!.add(label);
    threeScene!.add(trail);

    entry = { mesh, label, trail };
    threeCubes.set(s.id, entry);
    return entry;
  }

  function renderCubes(now: number) {
    if (!threeScene || !threeCamera || !threeRenderer) return;

    const n = sensorList.length;
    // Arrange in a grid
    const cols = Math.ceil(Math.sqrt(n));
    const spacing = 3.5;

    for (let i = 0; i < n; i++) {
      const s = sensorList[i];
      const stale = now - s.lastUpdate > STALE_MS;
      const { mesh, label, trail } = getOrCreateCube(s);

      // Grid position
      const col = i % cols;
      const row = Math.floor(i / cols);
      const gx = (col - (cols - 1) / 2) * spacing;
      const gz = (row - (Math.ceil(n / cols) - 1) / 2) * spacing;

      // Integrate acceleration → velocity → position (simple Euler)
      const dt = 0.016; // ~60fps timestep
      const accelScale = 0.08; // tune how responsive movement is
      const friction = 0.92; // velocity damping (simulates drag)
      const boundRadius = 2.5; // elastic boundary distance from grid home

      // Accelerometer values drive velocity (x=lateral, y=vertical, z=depth)
      s.vx += s.x * accelScale * dt;
      s.vy += s.y * accelScale * dt;
      s.vz += s.z * accelScale * dt;

      // Apply friction so cubes don't drift forever
      s.vx *= friction;
      s.vy *= friction;
      s.vz *= friction;

      // Integrate velocity → position
      s.px += s.vx;
      s.py += s.vy;
      s.pz += s.vz;

      // Elastic tether: pull back toward grid home when too far
      const dist = Math.sqrt(s.px * s.px + s.py * s.py + s.pz * s.pz);
      if (dist > boundRadius) {
        const pull = (dist - boundRadius) * 0.05;
        s.px -= (s.px / dist) * pull;
        s.py -= (s.py / dist) * pull;
        s.pz -= (s.pz / dist) * pull;
      }

      mesh.position.set(gx + s.px, s.py, gz + s.pz);

      // Gyroscope drives rotation (angular velocity)
      mesh.rotation.x += s.y * 0.02;
      mesh.rotation.y += s.x * 0.02;
      mesh.rotation.z += s.z * 0.01;

      // Scale pulsation from magnitude
      const scale = 1.0 + Math.min(0.5, s.mag * 0.2);
      mesh.scale.setScalar(scale);

      // Emissive intensity for activity
      const mat = mesh.material as THREE.MeshStandardMaterial;
      mat.emissiveIntensity = stale ? 0.05 : 0.15 + s.mag * 0.3;
      mat.opacity = stale ? 0.15 : 0.45;

      // Label position
      label.position.set(gx, -2.0, gz);
      label.material.opacity = stale ? 0.3 : 0.8;

      // Trail follows actual 3D position
      s.trail.push({ x: mesh.position.x, y: mesh.position.y, mag: mesh.position.z });
      if (s.trail.length > TRAIL_LEN) s.trail.shift();
      const positions = trail.geometry.attributes.position as THREE.BufferAttribute;
      for (let j = 0; j < TRAIL_LEN; j++) {
        if (j < s.trail.length) {
          positions.setXYZ(j, s.trail[j].x, s.trail[j].y, s.trail[j].mag);
        } else {
          positions.setXYZ(j, mesh.position.x, mesh.position.y, mesh.position.z);
        }
      }
      positions.needsUpdate = true;
      trail.geometry.setDrawRange(0, s.trail.length);
    }

    // Focus animation: smoothly move OrbitControls target to focused sensor
    if (focusedSensorId && threeControls) {
      const entry = threeCubes.get(focusedSensorId);
      if (entry) {
        focusTarget.copy(entry.mesh.position);
        threeControls.target.lerp(focusTarget, 0.08);
        // Move camera closer to focused cube
        focusCamTarget.set(
          entry.mesh.position.x + 3,
          entry.mesh.position.y + 3,
          entry.mesh.position.z + 5
        );
        threeCamera.position.lerp(focusCamTarget, 0.04);

        // Highlight focused cube, dim others
        for (const [id, c] of threeCubes) {
          const mat = c.mesh.material as THREE.MeshStandardMaterial;
          if (id === focusedSensorId) {
            mat.emissiveIntensity = 0.5 + Math.sin(now * 0.005) * 0.15;
          } else {
            mat.emissiveIntensity = 0.05;
            mat.opacity = 0.1;
            c.label.material.opacity = 0.2;
          }
        }
      }
    } else {
      // Restore all cubes to normal when unfocused
      for (const [id, c] of threeCubes) {
        const s = sensorMap.get(id);
        const stale = s ? now - s.lastUpdate > STALE_MS : true;
        const mat = c.mesh.material as THREE.MeshStandardMaterial;
        mat.opacity = stale ? 0.15 : 0.45;
        c.label.material.opacity = stale ? 0.3 : 0.8;
      }
    }

    // Update OrbitControls
    if (threeControls) threeControls.update();

    threeRenderer.render(threeScene, threeCamera);
  }

  // ── Main render loop ──────────────────────────────────────────────
  function render() {
    const now = Date.now();

    // Write current smoothed values into wave buffers at constant rate
    advanceWaveBuffers(now);

    // Handle mode transitions
    if (mode !== prevMode) {
      if (prevMode === 'cubes') disposeThree();
      if (mode === 'cubes') initThree();
      prevMode = mode;
    }

    if (mode === 'cubes') {
      renderCubes(now);
    } else if (ctx && canvas2d && cssW > 0) {
      if (mode === 'field') renderField(cssW, cssH, now);
      else if (mode === 'waves') renderWaves(cssW, cssH, now);
      else if (mode === 'radial') renderRadial(cssW, cssH, now);

      ctx.font = '10px Inter, system-ui, sans-serif';
      ctx.textAlign = 'right';
      ctx.fillStyle = 'rgba(156, 163, 175, 0.5)';
      const active = sensorList.filter(s => now - s.lastUpdate < STALE_MS).length;
      ctx.fillText(`${active}/${sensorList.length} active`, cssW - 10, 16);
    }

    rafId = requestAnimationFrame(render);
  }

  // ── Canvas resize ─────────────────────────────────────────────────
  function resizeCanvas() {
    if (!canvas2d) return;
    const rect = canvas2d.parentElement?.getBoundingClientRect();
    if (!rect || rect.width === 0 || rect.height === 0) return;
    const dpr = window.devicePixelRatio || 1;
    cssW = rect.width; cssH = rect.height;
    canvas2d.width = cssW * dpr; canvas2d.height = cssH * dpr;
    canvas2d.style.width = cssW + 'px'; canvas2d.style.height = cssH + 'px';
    ctx = canvas2d.getContext('2d');
    if (ctx) { ctx.setTransform(dpr, 0, 0, dpr, 0, 0); ctx.fillStyle = '#0a0814'; ctx.fillRect(0, 0, cssW, cssH); }
    resizeThree();
  }

  // ── Lifecycle ─────────────────────────────────────────────────────
  let handleCompositeMeasurement: ((e: Event) => void) | null = null;
  let handleAccumulatorEvent: ((e: Event) => void) | null = null;
  let resizeObserver: ResizeObserver | null = null;

  onMount(() => {
    sensors.forEach(s => {
      const state = getOrCreateSensor(s.sensor_id);
      if (s.orientation && typeof s.orientation === 'object') {
        if ('x' in s.orientation) state.x = s.orientation.x || 0;
        if ('y' in s.orientation) state.y = s.orientation.y || 0;
        if ('z' in s.orientation) state.z = s.orientation.z || 0;
      }
    });

    resizeCanvas();
    const wrapper = canvas2d?.parentElement;
    if (wrapper) {
      resizeObserver = new ResizeObserver(() => resizeCanvas());
      resizeObserver.observe(wrapper);
    }
    if (mode === 'cubes') initThree();
    rafId = requestAnimationFrame(render);

    handleCompositeMeasurement = (e: Event) => {
      const { sensor_id, attribute_id, payload } = (e as CustomEvent).detail;
      if (IMU_ATTRS.has(attribute_id)) ingestMeasurement(sensor_id, attribute_id, payload);
    };
    handleAccumulatorEvent = (e: Event) => {
      const d = (e as CustomEvent).detail;
      if (!IMU_ATTRS.has(d?.attribute_id)) return;
      let payload = null;
      if (Array.isArray(d.data) && d.data.length > 0) payload = d.data[d.data.length - 1]?.payload;
      else if (d.data?.payload !== undefined) payload = d.data.payload;
      if (payload != null) ingestMeasurement(d.sensor_id, d.attribute_id, payload);
    };
    window.addEventListener("composite-measurement-event", handleCompositeMeasurement);
    window.addEventListener("accumulator-data-event", handleAccumulatorEvent);
  });

  onDestroy(() => {
    if (rafId) cancelAnimationFrame(rafId);
    disposeThree();
    if (handleCompositeMeasurement) window.removeEventListener("composite-measurement-event", handleCompositeMeasurement);
    if (handleAccumulatorEvent) window.removeEventListener("accumulator-data-event", handleAccumulatorEvent);
    if (resizeObserver) resizeObserver.disconnect();
  });
</script>

<div class="imu-container">
  <div class="imu-header">
    <div class="imu-header-row">
      <h2>IMU Visualization</h2>
      <span class="sensor-count">{sensors.length} sensors</span>
    </div>
    <div class="imu-header-row">
      <div class="mode-switcher">
        <button class:active={mode === 'waves'} onclick={() => mode = 'waves'}>Waves</button>
        <button class:active={mode === 'field'} onclick={() => mode = 'field'}>Field</button>
        <button class:active={mode === 'radial'} onclick={() => mode = 'radial'}>Radial</button>
        <button class:active={mode === 'cubes'} onclick={() => mode = 'cubes'}>3D</button>
      </div>
      {#if mode === 'waves'}
        <div class="time-switcher">
          {#each TIME_WINDOWS as tw}
            <button class:active={timeWindow === tw} onclick={() => timeWindow = tw}>{tw}s</button>
          {/each}
        </div>
      {/if}
    </div>
  </div>
  <div class="canvas-wrapper">
    <canvas bind:this={canvas2d} class:hidden={mode === 'cubes'}></canvas>
    <div bind:this={container3d} class="three-container" class:hidden={mode !== 'cubes'}></div>
  </div>
</div>

<style>
  .imu-container {
    background: #0a0814;
    border-radius: 0.75rem;
    border: 1px solid rgba(75, 85, 99, 0.4);
    height: 100%;
    min-height: 400px;
    display: flex;
    flex-direction: column;
    overflow: hidden;
  }
  .imu-header {
    display: flex;
    flex-direction: column;
    padding: 0.5rem 1rem;
    border-bottom: 1px solid rgba(75, 85, 99, 0.3);
    flex-shrink: 0;
    gap: 0.4rem;
  }
  .imu-header-row {
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: 0.75rem;
    flex-wrap: wrap;
  }
  .imu-header h2 {
    font-size: 0.8rem;
    font-weight: 600;
    color: #e2e0f0;
    margin: 0;
    white-space: nowrap;
  }
  .mode-switcher, .time-switcher {
    display: flex;
    border-radius: 6px;
    overflow: hidden;
    border: 1px solid rgba(139, 92, 246, 0.3);
  }
  .time-switcher {
    border-color: rgba(59, 130, 246, 0.3);
  }
  .mode-switcher button, .time-switcher button {
    padding: 3px 10px;
    font-size: 0.65rem;
    font-weight: 500;
    background: transparent;
    color: #7c6a9e;
    border: none;
    cursor: pointer;
    transition: all 0.15s;
    letter-spacing: 0.02em;
  }
  .time-switcher button {
    color: #6a7c9e;
    padding: 3px 8px;
  }
  .mode-switcher button:not(:last-child) {
    border-right: 1px solid rgba(139, 92, 246, 0.3);
  }
  .time-switcher button:not(:last-child) {
    border-right: 1px solid rgba(59, 130, 246, 0.3);
  }
  .mode-switcher button.active {
    background: rgba(139, 92, 246, 0.35);
    color: #e9d5ff;
  }
  .time-switcher button.active {
    background: rgba(59, 130, 246, 0.35);
    color: #bfdbfe;
  }
  .mode-switcher button:hover:not(.active) {
    background: rgba(139, 92, 246, 0.12);
  }
  .time-switcher button:hover:not(.active) {
    background: rgba(59, 130, 246, 0.12);
  }
  .sensor-count {
    font-size: 0.65rem;
    color: #6b7280;
    font-family: monospace;
    white-space: nowrap;
  }
  .canvas-wrapper {
    flex: 1;
    min-height: 0;
    position: relative;
  }
  .canvas-wrapper canvas {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
  }
  .three-container {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
  }
  .three-container :global(canvas) {
    width: 100% !important;
    height: 100% !important;
  }
  .hidden {
    display: none !important;
  }
</style>
