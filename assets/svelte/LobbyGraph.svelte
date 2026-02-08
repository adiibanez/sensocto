<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import Graph from "graphology";
  import Sigma from "sigma";
  import EdgeCurveProgram from "@sigma/edge-curve";
  import forceAtlas2 from "graphology-layout-forceatlas2";

  interface Room {
    id: string;
    name: string;
    sensor_count: number;
  }

  interface User {
    connector_id: string;
    connector_name: string;
    sensor_count: number;
    sensors: Array<{ sensor_id: string; sensor_name: string }>;
    attributes_summary: Array<{ type: string; count: number; latest_value: any }>;
  }

  interface Sensor {
    sensor_id: string;
    sensor_name: string;
    connector_id: string;
    connector_name: string;
    attributes: Record<string, Attribute>;
  }

  interface Attribute {
    attribute_id: string;
    attribute_type: string;
    attribute_name?: string;
    lastvalue?: { payload: any; timestamp: number };
  }

  interface Props {
    rooms?: Room[];
    users?: User[];
    sensors?: Record<string, Sensor>;
  }

  let {
    rooms = [],
    users = [],
    sensors = {}
  }: Props = $props();

  let container: HTMLDivElement;
  let graph: Graph;
  let sigma: Sigma | null = null;
  let selectedNode = $state<string | null>(null);
  let hoveredNode = $state<string | null>(null);
  let hoverDetails = $state<any>(null);
  let selectedDetails = $state<any>(null);
  let mouseX = $state(0);
  let mouseY = $state(0);
  let isLayoutRunning = $state(false);
  let isFullscreen = $state(false);
  let showExportModal = $state(false);
  let exportFormat = $state<"png" | "jpeg">("png");
  let exportScale = $state(2);
  let exportBackground = $state(true);
  let isExporting = $state(false);
  let isRecording = $state(false);
  let recordingSeconds = $state(0);
  let mediaRecorder: MediaRecorder | null = null;
  let recordedChunks: Blob[] = [];
  let recordingTimer: ReturnType<typeof setInterval> | null = null;
  let recordingRaf: number | null = null;
  let recordingCanvas: HTMLCanvasElement | null = null;
  let graphRoot: HTMLDivElement;

  // Plasma crackle sound engine — electrical discharge / Knistern
  let soundEnabled = $state(false);
  let audioCtx: AudioContext | null = null;
  let lastSoundTime = 0;
  // ~6.7 events/sec — cortical theta window (150-300ms), proven
  // sonification IOI range. Each crackle is perceptually discrete
  // before the ~10Hz flutter/fusion threshold.
  const SOUND_DEBOUNCE_MS = 150;
  let noiseBuffer: AudioBuffer | null = null;

  function ensureAudioCtx() {
    if (!audioCtx) {
      audioCtx = new AudioContext();
    }
    if (audioCtx.state === "suspended") {
      audioCtx.resume();
    }
    if (!noiseBuffer) {
      const len = Math.ceil(audioCtx.sampleRate * 0.05);
      noiseBuffer = audioCtx.createBuffer(1, len, audioCtx.sampleRate);
      const data = noiseBuffer.getChannelData(0);
      for (let i = 0; i < len; i++) {
        data[i] = Math.random() * 2 - 1;
      }
    }
    return audioCtx;
  }

  function playCrackle() {
    if (!soundEnabled) return;

    const now = performance.now();
    if (now - lastSoundTime < SOUND_DEBOUNCE_MS) return;
    lastSoundTime = now;

    const ctx = ensureAudioCtx();
    const t = ctx.currentTime;

    const duration = 0.004 + Math.random() * 0.014;
    const volume = 0.04 + Math.random() * 0.08;

    const noise = ctx.createBufferSource();
    noise.buffer = noiseBuffer!;

    const bp = ctx.createBiquadFilter();
    bp.type = "bandpass";
    bp.frequency.value = 2500 + Math.random() * 5500;
    bp.Q.value = 0.8 + Math.random() * 2.5;

    const hp = ctx.createBiquadFilter();
    hp.type = "highpass";
    hp.frequency.value = 800 + Math.random() * 1200;

    const gain = ctx.createGain();
    gain.gain.setValueAtTime(volume, t);
    gain.gain.exponentialRampToValueAtTime(0.001, t + duration);

    noise.connect(bp);
    bp.connect(hp);
    hp.connect(gain);
    gain.connect(ctx.destination);

    noise.start(t, Math.random() * 0.03, duration + 0.01);

    if (Math.random() < 0.25) {
      const osc = ctx.createOscillator();
      osc.type = "sine";
      const startFreq = 2000 + Math.random() * 5000;
      osc.frequency.setValueAtTime(startFreq, t);
      osc.frequency.exponentialRampToValueAtTime(150 + Math.random() * 300, t + 0.012);

      const oscGain = ctx.createGain();
      oscGain.gain.setValueAtTime(volume * 0.35, t);
      oscGain.gain.exponentialRampToValueAtTime(0.001, t + 0.012);

      osc.connect(oscGain);
      oscGain.connect(ctx.destination);
      osc.start(t);
      osc.stop(t + 0.015);
    }

    if (Math.random() < 0.15) {
      const noise2 = ctx.createBufferSource();
      noise2.buffer = noiseBuffer!;

      const bp2 = ctx.createBiquadFilter();
      bp2.type = "bandpass";
      bp2.frequency.value = 4000 + Math.random() * 4000;
      bp2.Q.value = 1 + Math.random() * 3;

      const gain2 = ctx.createGain();
      const d2 = 0.002 + Math.random() * 0.006;
      gain2.gain.setValueAtTime(volume * 0.6, t + 0.005);
      gain2.gain.exponentialRampToValueAtTime(0.001, t + 0.005 + d2);

      noise2.connect(bp2);
      bp2.connect(gain2);
      gain2.connect(ctx.destination);
      noise2.start(t + 0.005, Math.random() * 0.03, d2 + 0.01);
    }
  }

  function toggleSound() {
    soundEnabled = !soundEnabled;
    if (soundEnabled) {
      ensureAudioCtx();
    }
  }

  // Set of nodes to highlight (hovered node + all connected neighbors)
  let highlightedNodes = new Set<string>();

  // Collect all descendant nodes (children) from a given node
  // In our graph structure: user -> sensors -> attributes
  function collectDescendants(nodeId: string, collected: Set<string>) {
    if (!graph) return;

    // Get all outgoing edges (children)
    const outEdges = graph.outEdges(nodeId);
    for (const edge of outEdges) {
      const target = graph.target(edge);
      if (!collected.has(target)) {
        collected.add(target);
        collectDescendants(target, collected);
      }
    }

    // Also collect parent nodes going upward (for context)
    const inEdges = graph.inEdges(nodeId);
    for (const edge of inEdges) {
      const source = graph.source(edge);
      if (!collected.has(source)) {
        collected.add(source);
      }
    }
  }

  const nodeColors = {
    room: "#3b82f6",      // blue
    user: "#22c55e",      // green
    sensor: "#f97316",    // orange
    attribute: "#8b5cf6"  // purple
  };

  // Base node sizes (will be scaled based on graph size)
  const baseNodeSizes = {
    room: 16,
    user: 12,
    sensor: 8,
    attribute: 4
  };

  let scaledNodeSizes = $state({ ...baseNodeSizes });

  function calculateNodeScale(nodeCount: number): number {
    if (nodeCount <= 30) return 1.4;
    if (nodeCount <= 80) return 1.1;
    if (nodeCount <= 200) return 0.85;
    if (nodeCount <= 500) return 0.7;
    if (nodeCount <= 1000) return 0.55;
    return 0.4;
  }

  // Slight random variation for organic feel (±15%)
  function jitterSize(base: number): number {
    return base * (0.85 + Math.random() * 0.3);
  }

  // Random curvature for organic edge feel
  function randomCurvature(): number {
    const sign = Math.random() > 0.5 ? 1 : -1;
    return sign * (0.15 + Math.random() * 0.35);
  }

  function buildGraph() {
    graph = new Graph();

    // First, estimate total node count to calculate scale
    let estimatedNodeCount = rooms.length + users.length;
    for (const sensor of Object.values(sensors)) {
      estimatedNodeCount += 1; // sensor node
      estimatedNodeCount += Object.keys(sensor.attributes || {}).length; // attribute nodes
    }

    // Calculate and apply scale factor
    const scale = calculateNodeScale(estimatedNodeCount);
    scaledNodeSizes = {
      room: baseNodeSizes.room * scale,
      user: baseNodeSizes.user * scale,
      sensor: baseNodeSizes.sensor * scale,
      attribute: baseNodeSizes.attribute * scale
    };

    // Add room nodes
    for (const room of rooms) {
      graph.addNode(`room:${room.id}`, {
        label: room.name,
        size: jitterSize(scaledNodeSizes.room),
        color: nodeColors.room,
        nodeType: "room",
        data: room,
        x: Math.random() * 100,
        y: Math.random() * 100
      });
    }

    // Add user/connector nodes
    for (const user of users) {
      graph.addNode(`user:${user.connector_id}`, {
        label: user.connector_name,
        size: jitterSize(scaledNodeSizes.user + Math.min(user.sensor_count * scale, 8 * scale)),
        color: nodeColors.user,
        nodeType: "user",
        data: user,
        x: Math.random() * 100,
        y: Math.random() * 100
      });
    }

    // Add sensor nodes and edges
    for (const [sensorId, sensor] of Object.entries(sensors)) {
      const sensorNodeId = `sensor:${sensorId}`;
      const attrCount = Object.keys(sensor.attributes || {}).length;

      graph.addNode(sensorNodeId, {
        label: sensor.sensor_name || sensorId.substring(0, 12),
        size: jitterSize(scaledNodeSizes.sensor + Math.min(attrCount * 1.5 * scale, 6 * scale)),
        color: nodeColors.sensor,
        nodeType: "sensor",
        data: sensor,
        x: Math.random() * 100,
        y: Math.random() * 100
      });

      // Connect sensor to its user/connector
      const userNodeId = `user:${sensor.connector_id}`;
      if (graph.hasNode(userNodeId)) {
        graph.addEdge(userNodeId, sensorNodeId, {
          size: Math.max(0.3, 0.7 * scale),
          color: "rgba(55, 65, 81, 0.35)",
          curvature: randomCurvature()
        });
      }

      // Add attribute nodes
      for (const [attrId, attr] of Object.entries(sensor.attributes || {})) {
        const attrNodeId = `attr:${sensorId}:${attrId}`;
        const attrLabel = attr.attribute_name || attr.attribute_id;

        // Color attributes by type
        let attrColor = nodeColors.attribute;
        if (attr.attribute_type === "heartrate" || attr.attribute_id.includes("heart")) {
          attrColor = "#ef4444"; // red
        } else if (attr.attribute_type === "battery") {
          attrColor = "#eab308"; // yellow
        } else if (attr.attribute_type === "location" || attr.attribute_id.includes("geo")) {
          attrColor = "#06b6d4"; // cyan
        } else if (attr.attribute_type === "imu" || attr.attribute_id.includes("accelero")) {
          attrColor = "#a855f7"; // purple
        }

        graph.addNode(attrNodeId, {
          label: attrLabel,
          size: jitterSize(scaledNodeSizes.attribute),
          color: attrColor,
          nodeType: "attribute",
          data: { ...attr, sensor_id: sensorId },
          x: Math.random() * 100,
          y: Math.random() * 100
        });

        graph.addEdge(sensorNodeId, attrNodeId, {
          size: Math.max(0.2, 0.4 * scale),
          color: "rgba(55, 65, 81, 0.25)",
          curvature: randomCurvature()
        });
      }
    }

    // Connect rooms to sensors if we have room data with sensor connections
    // (This would require additional data from the backend)
  }

  function runLayout() {
    if (!graph || graph.order === 0) return;

    isLayoutRunning = true;

    const nodeCount = graph.order;
    const iterations = nodeCount > 500 ? 200 : nodeCount > 200 ? 150 : 120;

    forceAtlas2.assign(graph, {
      iterations,
      settings: {
        gravity: 0.3,
        scalingRatio: nodeCount > 300 ? 20 : 12,
        strongGravityMode: false,
        barnesHutOptimize: nodeCount > 100,
        barnesHutTheta: 0.6,
        linLogMode: true,
        adjustSizes: true,
        edgeWeightInfluence: 1,
        slowDown: 2
      }
    });

    if (sigma) {
      sigma.refresh();
    }

    isLayoutRunning = false;
  }

  function initSigma() {
    if (!container || !graph) return;

    // Clear any existing sigma instance
    if (sigma) {
      sigma.kill();
    }

    // Calculate scale-aware settings
    const scale = scaledNodeSizes.sensor / baseNodeSizes.sensor;
    const labelThreshold = Math.max(2, 4 * scale);
    const labelSize = Math.max(8, Math.round(12 * scale));

    // Temporarily inject preserveDrawingBuffer:true for export support
    const origGetContext = HTMLCanvasElement.prototype.getContext;
    HTMLCanvasElement.prototype.getContext = function(type: string, opts?: any) {
      if (type === "webgl2" || type === "webgl" || type === "experimental-webgl") {
        opts = { ...opts, preserveDrawingBuffer: true };
      }
      return origGetContext.call(this, type, opts);
    } as any;

    sigma = new Sigma(graph, container, {
      renderLabels: true,
      labelRenderedSizeThreshold: labelThreshold,
      labelFont: "Inter, system-ui, sans-serif",
      labelSize: labelSize,
      labelWeight: "500",
      labelColor: { color: "#e5e7eb" },
      defaultNodeColor: "#6b7280",
      defaultEdgeColor: "rgba(55, 65, 81, 0.3)",
      defaultEdgeType: "curved",
      edgeProgramClasses: {
        curved: EdgeCurveProgram
      },
      allowInvalidContainer: true,
      labelDensity: scale < 0.7 ? 0.5 : 1,
      minCameraRatio: 0.1,
      maxCameraRatio: 10,
      // Node reducer: dim nodes that aren't highlighted
      nodeReducer: (node, data) => {
        if (highlightedNodes.size === 0) {
          return data;
        }
        if (highlightedNodes.has(node)) {
          return { ...data, zIndex: 1 };
        }
        return {
          ...data,
          color: "rgba(45, 55, 72, 0.3)",
          zIndex: 0
        };
      },
      edgeReducer: (edge, data) => {
        if (highlightedNodes.size === 0) {
          return data;
        }
        const source = graph.source(edge);
        const target = graph.target(edge);
        if (highlightedNodes.has(source) && highlightedNodes.has(target)) {
          return { ...data, color: "#c026d3", size: (data.size || 0.5) * 1.5, zIndex: 1 };
        }
        return {
          ...data,
          color: "rgba(55, 65, 81, 0.4)",
          zIndex: 0
        };
      }
    });

    // Restore original getContext
    HTMLCanvasElement.prototype.getContext = origGetContext;

    // Track mouse position for hover tooltip
    container.addEventListener("mousemove", (e: MouseEvent) => {
      mouseX = e.clientX;
      mouseY = e.clientY;
    });

    // Handle node hover - highlight connected subgraph
    sigma.on("enterNode", ({ node }) => {
      hoveredNode = node;
      const attrs = graph.getNodeAttributes(node);
      hoverDetails = {
        id: node,
        label: attrs.label,
        type: attrs.nodeType,
        data: attrs.data
      };
      document.body.style.cursor = "pointer";

      highlightedNodes = new Set([node]);
      collectDescendants(node, highlightedNodes);
      sigma?.refresh();
    });

    sigma.on("leaveNode", () => {
      document.body.style.cursor = "default";
      hoveredNode = null;
      hoverDetails = null;

      if (selectedNode) {
        highlightedNodes = new Set([selectedNode]);
        collectDescendants(selectedNode, highlightedNodes);
      } else {
        highlightedNodes = new Set();
      }
      sigma?.refresh();
    });

    // Handle node click - persist selection in bottom bar
    sigma.on("clickNode", ({ node }) => {
      if (selectedNode === node) {
        selectedNode = null;
        selectedDetails = null;
        highlightedNodes = new Set();
      } else {
        selectedNode = node;
        const attrs = graph.getNodeAttributes(node);
        selectedDetails = {
          id: node,
          label: attrs.label,
          type: attrs.nodeType,
          data: attrs.data
        };
        highlightedNodes = new Set([node]);
        collectDescendants(node, highlightedNodes);
      }
      sigma?.refresh();
    });

    // Handle background click to deselect
    sigma.on("clickStage", () => {
      selectedNode = null;
      selectedDetails = null;
      highlightedNodes = new Set();
      sigma?.refresh();
    });

    // Run initial layout
    runLayout();
  }

  function handleZoomIn() {
    if (sigma) {
      const camera = sigma.getCamera();
      camera.animatedZoom({ duration: 200 });
    }
  }

  function handleZoomOut() {
    if (sigma) {
      const camera = sigma.getCamera();
      camera.animatedUnzoom({ duration: 200 });
    }
  }

  function handleRelayout() {
    runLayout();
    if (sigma) {
      sigma.refresh();
    }
  }

  function handleFullscreen() {
    isFullscreen = !isFullscreen;
    setTimeout(() => sigma?.refresh(), 50);
  }

  function onKeydown(e: KeyboardEvent) {
    if (e.key === "Escape") {
      if (isRecording) {
        stopRecording();
      } else if (showExportModal) {
        showExportModal = false;
      } else if (isFullscreen) {
        isFullscreen = false;
        setTimeout(() => sigma?.refresh(), 50);
      }
    }
  }

  function exportGraph() {
    if (!sigma || !container) return;
    isExporting = true;

    try {
      // Force synchronous re-render so WebGL buffers are filled
      sigma.refresh();

      const canvases = container.querySelectorAll("canvas");
      if (canvases.length === 0) { isExporting = false; return; }

      const baseWidth = container.offsetWidth;
      const baseHeight = container.offsetHeight;
      const width = Math.round(baseWidth * exportScale);
      const height = Math.round(baseHeight * exportScale);

      const offscreen = document.createElement("canvas");
      offscreen.width = width;
      offscreen.height = height;
      const ctx = offscreen.getContext("2d");
      if (!ctx) { isExporting = false; return; }

      if (exportBackground) {
        const grad = ctx.createLinearGradient(0, 0, width, height);
        grad.addColorStop(0, "#0f172a");
        grad.addColorStop(1, "#1e293b");
        ctx.fillStyle = grad;
        ctx.fillRect(0, 0, width, height);
      }

      // Capture immediately after render — WebGL buffer is still filled
      canvases.forEach(canvas => {
        ctx.drawImage(canvas, 0, 0, width, height);
      });

      // Composite glow overlay
      if (glowCanvas && glowCanvas.width > 0) {
        ctx.drawImage(glowCanvas, 0, 0, width, height);
      }

      const mimeType = exportFormat === "jpeg" ? "image/jpeg" : "image/png";
      const quality = exportFormat === "jpeg" ? 0.95 : undefined;

      offscreen.toBlob((blob) => {
        if (!blob) { isExporting = false; return; }
        const url = URL.createObjectURL(blob);
        const a = document.createElement("a");
        a.href = url;
        a.download = `sensocto-graph-${width}x${height}.${exportFormat}`;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        URL.revokeObjectURL(url);
        showExportModal = false;
        isExporting = false;
      }, mimeType, quality);
    } catch (err) {
      console.error("Export failed:", err);
      isExporting = false;
    }
  }

  function startRecording() {
    if (!container) return;

    const canvases = container.querySelectorAll("canvas");
    if (canvases.length === 0) return;

    const w = container.offsetWidth;
    const h = container.offsetHeight;

    recordingCanvas = document.createElement("canvas");
    recordingCanvas.width = w;
    recordingCanvas.height = h;
    const ctx = recordingCanvas.getContext("2d");
    if (!ctx) return;

    // Composite loop at ~30fps
    function drawFrame() {
      if (!ctx || !recordingCanvas) return;
      // Draw background
      const grad = ctx.createLinearGradient(0, 0, recordingCanvas.width, recordingCanvas.height);
      grad.addColorStop(0, "#0f172a");
      grad.addColorStop(1, "#1e293b");
      ctx.fillStyle = grad;
      ctx.fillRect(0, 0, recordingCanvas.width, recordingCanvas.height);
      // Composite sigma canvases
      canvases.forEach(c => {
        ctx.drawImage(c, 0, 0, recordingCanvas!.width, recordingCanvas!.height);
      });
      // Composite glow overlay
      if (glowCanvas && glowCanvas.width > 0) {
        ctx.drawImage(glowCanvas, 0, 0, recordingCanvas!.width, recordingCanvas!.height);
      }
      recordingRaf = requestAnimationFrame(drawFrame);
    }

    drawFrame();

    const stream = recordingCanvas.captureStream(30);
    const mimeType = MediaRecorder.isTypeSupported("video/webm;codecs=vp9")
      ? "video/webm;codecs=vp9"
      : "video/webm";

    recordedChunks = [];
    mediaRecorder = new MediaRecorder(stream, {
      mimeType,
      videoBitsPerSecond: 8_000_000
    });

    mediaRecorder.ondataavailable = (e) => {
      if (e.data.size > 0) recordedChunks.push(e.data);
    };

    mediaRecorder.onstop = () => {
      const blob = new Blob(recordedChunks, { type: mimeType });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `sensocto-graph-${w}x${h}.webm`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
      recordedChunks = [];
    };

    mediaRecorder.start(100); // collect data every 100ms
    isRecording = true;
    recordingSeconds = 0;
    recordingTimer = setInterval(() => { recordingSeconds += 1; }, 1000);
  }

  function stopRecording() {
    if (mediaRecorder && mediaRecorder.state !== "inactive") {
      mediaRecorder.stop();
    }
    if (recordingRaf !== null) {
      cancelAnimationFrame(recordingRaf);
      recordingRaf = null;
    }
    if (recordingTimer !== null) {
      clearInterval(recordingTimer);
      recordingTimer = null;
    }
    recordingCanvas = null;
    mediaRecorder = null;
    isRecording = false;
    recordingSeconds = 0;
  }

  function toggleRecording() {
    if (isRecording) stopRecording();
    else startRecording();
  }

  function formatRecordingTime(seconds: number): string {
    const m = Math.floor(seconds / 60);
    const s = seconds % 60;
    return `${m}:${s.toString().padStart(2, "0")}`;
  }

  function getNodeTypeIcon(type: string): string {
    switch (type) {
      case "room": return "🏠";
      case "user": return "👤";
      case "sensor": return "📡";
      case "attribute": return "📊";
      default: return "•";
    }
  }

  function formatAttributeValue(data: any): string {
    if (!data?.lastvalue?.payload) return "No data";
    const payload = data.lastvalue.payload;
    if (typeof payload === "object") {
      return JSON.stringify(payload, null, 2);
    }
    return String(payload);
  }

  function getHoverSummary(details: any): string {
    if (!details) return "";
    switch (details.type) {
      case "user":
        return `${details.data.sensor_count} sensors`;
      case "sensor":
        return `${Object.keys(details.data.attributes || {}).length} attrs`;
      case "attribute": {
        const val = details.data?.lastvalue?.payload;
        if (val == null) return details.data.attribute_type;
        const short = typeof val === "object" ? JSON.stringify(val) : String(val);
        return short.length > 30 ? short.slice(0, 27) + "..." : short;
      }
      case "room":
        return `${details.data.sensor_count} sensors`;
      default:
        return "";
    }
  }

  // Track active pulsation animations: nodeId => {timeout, baseSize, originalColor}
  // Store original values to prevent compounding growth from rapid events
  let activePulsations = new Map<string, {timeout: number, baseSize: number, originalColor: string}>();

  // Glow overlay system — electric plasma halo on pulsating nodes
  let glowCanvas: HTMLCanvasElement;
  let glowCtx: CanvasRenderingContext2D | null = null;
  let glowRaf: number | null = null;
  let activeGlows = new Map<string, { start: number }>();
  const GLOW_DURATION_MS = 350;

  function startGlowLoop() {
    if (glowRaf !== null) return;
    function tick() {
      renderGlows();
      if (activeGlows.size > 0) {
        glowRaf = requestAnimationFrame(tick);
      } else {
        glowRaf = null;
      }
    }
    glowRaf = requestAnimationFrame(tick);
  }

  function renderGlows() {
    if (!glowCanvas || !sigma || !graph) return;
    if (!glowCtx) glowCtx = glowCanvas.getContext("2d");
    if (!glowCtx) return;

    const w = glowCanvas.clientWidth;
    const h = glowCanvas.clientHeight;
    const dpr = window.devicePixelRatio || 1;
    if (glowCanvas.width !== w * dpr || glowCanvas.height !== h * dpr) {
      glowCanvas.width = w * dpr;
      glowCanvas.height = h * dpr;
      glowCtx.setTransform(dpr, 0, 0, dpr, 0, 0);
    }

    glowCtx.clearRect(0, 0, w, h);
    const now = performance.now();

    for (const [nodeId, glow] of activeGlows) {
      const elapsed = now - glow.start;
      if (elapsed > GLOW_DURATION_MS) {
        activeGlows.delete(nodeId);
        continue;
      }

      if (!graph.hasNode(nodeId)) {
        activeGlows.delete(nodeId);
        continue;
      }

      // Skip rendering glows for offscreen nodes
      if (!isNodeInViewport(nodeId)) continue;

      const progress = elapsed / GLOW_DURATION_MS;
      const alpha = 0.7 * (1 - progress * progress);
      const nodeAttrs = graph.getNodeAttributes(nodeId);
      const viewPos = sigma.graphToViewport({ x: nodeAttrs.x, y: nodeAttrs.y });
      const baseSize = nodeAttrs.size || 4;
      const camera = sigma.getCamera();
      const ratio = camera.ratio || 1;
      const displaySize = (baseSize / ratio) * 2;
      const glowRadius = displaySize * (2.5 + progress * 1.5);

      const grad = glowCtx.createRadialGradient(
        viewPos.x, viewPos.y, displaySize * 0.3,
        viewPos.x, viewPos.y, glowRadius
      );

      grad.addColorStop(0, `rgba(180, 255, 200, ${alpha})`);
      grad.addColorStop(0.4, `rgba(34, 197, 94, ${alpha * 0.5})`);
      grad.addColorStop(1, `rgba(34, 197, 94, 0)`);

      glowCtx.fillStyle = grad;
      glowCtx.beginPath();
      glowCtx.arc(viewPos.x, viewPos.y, glowRadius, 0, Math.PI * 2);
      glowCtx.fill();
    }
  }

  // Throttle sigma.refresh() to at most once per animation frame
  let refreshScheduled = false;
  function scheduleRefresh() {
    if (refreshScheduled) return;
    refreshScheduled = true;
    requestAnimationFrame(() => {
      refreshScheduled = false;
      if (sigma) {
        sigma.refresh();
      }
    });
  }

  // Lighten a hex color by mixing with white
  function lightenColor(hex: string, amount: number = 0.3): string {
    // Remove # if present
    const color = hex.replace('#', '');
    const r = parseInt(color.substring(0, 2), 16);
    const g = parseInt(color.substring(2, 4), 16);
    const b = parseInt(color.substring(4, 6), 16);

    // Mix with white
    const newR = Math.min(255, Math.round(r + (255 - r) * amount));
    const newG = Math.min(255, Math.round(g + (255 - g) * amount));
    const newB = Math.min(255, Math.round(b + (255 - b) * amount));

    return `#${newR.toString(16).padStart(2, '0')}${newG.toString(16).padStart(2, '0')}${newB.toString(16).padStart(2, '0')}`;
  }

  // Check if a graph node is currently visible in the camera viewport.
  // Uses Sigma's graphToViewport to project node coords, then tests
  // against the canvas bounds with a generous margin for glow radius.
  function isNodeInViewport(nodeId: string): boolean {
    if (!sigma || !graph || !graph.hasNode(nodeId)) return false;
    const attrs = graph.getNodeAttributes(nodeId);
    const vp = sigma.graphToViewport({ x: attrs.x, y: attrs.y });
    const w = container?.offsetWidth || 0;
    const h = container?.offsetHeight || 0;
    const margin = 80;
    return vp.x >= -margin && vp.x <= w + margin && vp.y >= -margin && vp.y <= h + margin;
  }

  // Pulsate a node with subtle animation
  function pulsateNode(nodeId: string) {
    if (!graph || !graph.hasNode(nodeId)) return;

    // Check if this node is already pulsating
    const existing = activePulsations.get(nodeId);

    let baseSize: number;
    let originalColor: string;

    if (existing) {
      // Already pulsating - cancel timeout but keep original values
      clearTimeout(existing.timeout);
      baseSize = existing.baseSize;
      originalColor = existing.originalColor;
    } else {
      // First pulsation - capture current values as originals
      baseSize = graph.getNodeAttribute(nodeId, "size");
      originalColor = graph.getNodeAttribute(nodeId, "color");
    }

    // Subtle size increase (20% larger)
    const expandedSize = baseSize * 1.2;
    graph.setNodeAttribute(nodeId, "size", expandedSize);

    // Lighten the node's color
    const highlightColor = lightenColor(originalColor, 0.4);
    graph.setNodeAttribute(nodeId, "color", highlightColor);

    // Contract back after animation
    const timeout = setTimeout(() => {
      if (graph && graph.hasNode(nodeId)) {
        graph.setNodeAttribute(nodeId, "size", baseSize);
        graph.setNodeAttribute(nodeId, "color", originalColor);
        activePulsations.delete(nodeId);
        scheduleRefresh();
      }
    }, 250);

    activePulsations.set(nodeId, {timeout, baseSize, originalColor});

    activeGlows.set(nodeId, { start: performance.now() });
    startGlowLoop();

    scheduleRefresh();
  }

  // Handle graph activity events - pulsate sensor nodes (viewport-aware)
  function handleGraphActivity(event: CustomEvent) {
    const { sensor_id, attribute_ids } = event.detail;
    const sensorNodeId = `sensor:${sensor_id}`;
    let anyVisible = false;

    // Only pulsate nodes visible in the current viewport
    if (graph && graph.hasNode(sensorNodeId) && isNodeInViewport(sensorNodeId)) {
      pulsateNode(sensorNodeId);
      anyVisible = true;
    }

    if (attribute_ids && Array.isArray(attribute_ids)) {
      for (const attrId of attribute_ids) {
        const attrNodeId = `attr:${sensor_id}:${attrId}`;
        if (graph && graph.hasNode(attrNodeId) && isNodeInViewport(attrNodeId)) {
          pulsateNode(attrNodeId);
          anyVisible = true;
        }
      }
    }

    // Only play sound if at least one affected node is visible
    if (anyVisible) {
      playCrackle();
    }
  }

  // Handle composite measurement events for real-time updates (viewport-aware)
  function handleCompositeMeasurement(event: CustomEvent) {
    const { sensor_id, attribute_id, payload } = event.detail;
    const attrNodeId = `attr:${sensor_id}:${attribute_id}`;

    if (graph && graph.hasNode(attrNodeId)) {
      // Always update data (lightweight, no rendering cost)
      const attrs = graph.getNodeAttributes(attrNodeId);
      if (attrs.data) {
        attrs.data.lastvalue = { payload, timestamp: Date.now() };
      }

      // Only pulsate + glow if node is in the viewport
      if (isNodeInViewport(attrNodeId)) {
        pulsateNode(attrNodeId);

        const sensorNodeId = `sensor:${sensor_id}`;
        if (graph.hasNode(sensorNodeId) && isNodeInViewport(sensorNodeId)) {
          pulsateNode(sensorNodeId);
        }
      }
    }
  }

  // Track previous topology to avoid unnecessary rebuilds
  let prevSensorKeys = "";
  let prevUserCount = 0;
  let rebuildTimer: ReturnType<typeof setTimeout> | null = null;

  // Rebuild graph only when topology changes (sensors added/removed), debounced
  $effect(() => {
    // Access reactive deps
    const currentRooms = rooms;
    const currentUsers = users;
    const currentSensors = sensors;

    const sensorKeys = Object.keys(currentSensors || {}).sort().join(",");
    const userCount = (currentUsers || []).length;

    if (sensorKeys === prevSensorKeys && userCount === prevUserCount) {
      return; // topology unchanged, skip rebuild
    }

    prevSensorKeys = sensorKeys;
    prevUserCount = userCount;

    if (rebuildTimer) clearTimeout(rebuildTimer);
    rebuildTimer = setTimeout(() => {
      buildGraph();
      if (container) {
        initSigma();
      }
    }, 500);
  });

  onMount(() => {
    buildGraph();
    initSigma();
    window.addEventListener("composite-measurement-event", handleCompositeMeasurement as EventListener);
    window.addEventListener("graph-activity-event", handleGraphActivity as EventListener);
    window.addEventListener("keydown", onKeydown);
  });

  onDestroy(() => {
    if (isRecording) stopRecording();
    if (glowRaf !== null) { cancelAnimationFrame(glowRaf); glowRaf = null; }
    activeGlows.clear();
    if (audioCtx) {
      audioCtx.close();
      audioCtx = null;
    }
    window.removeEventListener("keydown", onKeydown);
    if (rebuildTimer) clearTimeout(rebuildTimer);
    if (sigma) {
      sigma.kill();
      sigma = null;
    }
    // Clear any pending pulsation timeouts
    for (const pulsation of activePulsations.values()) {
      clearTimeout(pulsation.timeout);
    }
    activePulsations.clear();
    window.removeEventListener("composite-measurement-event", handleCompositeMeasurement as EventListener);
    window.removeEventListener("graph-activity-event", handleGraphActivity as EventListener);
  });
</script>

<div class="lobby-graph" class:fullscreen={isFullscreen} bind:this={graphRoot}>
  <!-- Graph Container -->
  <div bind:this={container} class="graph-container"></div>

  <!-- Glow overlay canvas for plasma discharge halos -->
  <canvas bind:this={glowCanvas} class="glow-overlay"></canvas>

  <!-- Controls -->
  <div class="controls">
    <button onclick={handleZoomIn} title="Zoom In" class="control-btn">
      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0zM10 7v6m3-3H7" />
      </svg>
    </button>
    <button onclick={handleZoomOut} title="Zoom Out" class="control-btn">
      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0zM13 10H7" />
      </svg>
    </button>
<button onclick={handleRelayout} title="Re-layout" class="control-btn" disabled={isLayoutRunning}>
      <svg class="w-5 h-5" class:animate-spin={isLayoutRunning} fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
      </svg>
    </button>
    <div class="control-divider"></div>
    <button onclick={handleFullscreen} title={isFullscreen ? "Exit Fullscreen" : "Fullscreen"} class="control-btn">
      {#if isFullscreen}
        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 9V4.5M9 9H4.5M9 9L3.75 3.75M9 15v4.5M9 15H4.5M9 15l-5.25 5.25M15 9h4.5M15 9V4.5M15 9l5.25-5.25M15 15h4.5M15 15v4.5m0-4.5l5.25 5.25" />
        </svg>
      {:else}
        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3.75 3.75v4.5m0-4.5h4.5m-4.5 0L9 9M3.75 20.25v-4.5m0 4.5h4.5m-4.5 0L9 15M20.25 3.75h-4.5m4.5 0v4.5m0-4.5L15 9m5.25 11.25h-4.5m4.5 0v-4.5m0 4.5L15 15" />
        </svg>
      {/if}
    </button>
    <button onclick={() => showExportModal = true} title="Export Image" class="control-btn">
      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 16.5v2.25A2.25 2.25 0 005.25 21h13.5A2.25 2.25 0 0021 18.75V16.5M16.5 12L12 16.5m0 0L7.5 12m4.5 4.5V3" />
      </svg>
    </button>
    <button onclick={toggleRecording} title={isRecording ? "Stop Recording" : "Record Video"} class="control-btn" class:recording={isRecording}>
      {#if isRecording}
        <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
          <rect x="6" y="6" width="12" height="12" rx="1" />
        </svg>
      {:else}
        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <circle cx="12" cy="12" r="8" stroke-width="2" />
          <circle cx="12" cy="12" r="4" fill="currentColor" />
        </svg>
      {/if}
    </button>
    <div class="control-divider"></div>
    <button onclick={toggleSound} title={soundEnabled ? "Sound On" : "Sound Off"} class="control-btn" class:sound-active={soundEnabled}>
      {#if soundEnabled}
        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19.114 5.636a9 9 0 010 12.728M16.463 8.288a5.25 5.25 0 010 7.424M6.75 8.25l4.72-4.72a.75.75 0 011.28.53v15.88a.75.75 0 01-1.28.53l-4.72-4.72H4.51c-.88 0-1.704-.507-1.938-1.354A9.009 9.009 0 012.25 12c0-.83.112-1.633.322-2.396C2.806 8.756 3.63 8.25 4.51 8.25H6.75z" />
        </svg>
      {:else}
        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17.25 9.75L19.5 12m0 0l2.25 2.25M19.5 12l2.25-2.25M19.5 12l-2.25 2.25m-10.5-6l4.72-4.72a.75.75 0 011.28.53v15.88a.75.75 0 01-1.28.53l-4.72-4.72H4.51c-.88 0-1.704-.507-1.938-1.354A9.009 9.009 0 012.25 12c0-.83.112-1.633.322-2.396C2.806 8.756 3.63 8.25 4.51 8.25H6.75z" />
        </svg>
      {/if}
    </button>
  </div>

  <!-- Recording indicator -->
  {#if isRecording}
    <div class="recording-indicator">
      <span class="rec-dot"></span>
      <span class="rec-label">REC</span>
      <span class="rec-time">{formatRecordingTime(recordingSeconds)}</span>
    </div>
  {/if}

  <!-- Export Modal -->
  {#if showExportModal}
    <div class="export-overlay" onclick={() => showExportModal = false}>
      <div class="export-modal" onclick={(e) => e.stopPropagation()}>
        <div class="export-header">
          <span class="export-title">Export Graph</span>
          <button class="export-close" onclick={() => showExportModal = false}>
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        <div class="export-body">
          <div class="export-field">
            <label class="export-label">Format</label>
            <div class="export-options">
              <button class="export-option" class:active={exportFormat === "png"} onclick={() => exportFormat = "png"}>PNG</button>
              <button class="export-option" class:active={exportFormat === "jpeg"} onclick={() => exportFormat = "jpeg"}>JPEG</button>
            </div>
          </div>

          <div class="export-field">
            <label class="export-label">Resolution</label>
            <div class="export-options">
              {#each [1, 2, 4, 8] as scale}
                <button class="export-option" class:active={exportScale === scale} onclick={() => exportScale = scale}>
                  {scale}x
                </button>
              {/each}
            </div>
            <span class="export-hint">
              {Math.round((container?.offsetWidth || 1920) * exportScale)} x {Math.round((container?.offsetHeight || 1080) * exportScale)} px
            </span>
          </div>

          <div class="export-field">
            <label class="export-label">Background</label>
            <div class="export-options">
              <button class="export-option" class:active={exportBackground} onclick={() => exportBackground = true}>Dark</button>
              <button class="export-option" class:active={!exportBackground} onclick={() => exportBackground = false}>Transparent</button>
            </div>
            {#if !exportBackground && exportFormat === "jpeg"}
              <span class="export-hint export-warn">JPEG doesn't support transparency - will be black</span>
            {/if}
          </div>
        </div>

        <div class="export-footer">
          <button class="export-cancel" onclick={() => showExportModal = false}>Cancel</button>
          <button class="export-submit" onclick={exportGraph} disabled={isExporting}>
            {isExporting ? "Exporting..." : "Download"}
          </button>
        </div>
      </div>
    </div>
  {/if}

  <!-- Legend -->
  <div class="legend">
    <div class="legend-item">
      <span class="legend-dot" style="background: {nodeColors.room}"></span>
      <span>Rooms</span>
    </div>
    <div class="legend-item">
      <span class="legend-dot" style="background: {nodeColors.user}"></span>
      <span>Users</span>
    </div>
    <div class="legend-item">
      <span class="legend-dot" style="background: {nodeColors.sensor}"></span>
      <span>Sensors</span>
    </div>
    <div class="legend-item">
      <span class="legend-dot" style="background: {nodeColors.attribute}"></span>
      <span>Attributes</span>
    </div>
  </div>

  <!-- Compact Hover Tooltip (follows cursor) -->
  {#if hoverDetails && !selectedNode}
    <div class="hover-tooltip" style="left: {mouseX + 14}px; top: {mouseY - 10}px;">
      <span class="hover-icon" style="color: {nodeColors[hoverDetails.type] || '#9ca3af'}">{getNodeTypeIcon(hoverDetails.type)}</span>
      <span class="hover-label">{hoverDetails.label}</span>
      <span class="hover-meta">{getHoverSummary(hoverDetails)}</span>
    </div>
  {/if}

  <!-- Selected Node Bottom Bar -->
  {#if selectedDetails}
    <div class="bottom-bar">
      <div class="bottom-bar-main">
        <span class="bottom-bar-icon" style="color: {nodeColors[selectedDetails.type] || '#9ca3af'}">{getNodeTypeIcon(selectedDetails.type)}</span>
        <span class="bottom-bar-type">{selectedDetails.type}</span>
        <span class="bottom-bar-label">{selectedDetails.label}</span>
        <span class="bottom-bar-sep">|</span>

        {#if selectedDetails.type === "user"}
          <span class="bottom-bar-detail">Connector: {selectedDetails.data.connector_id}</span>
          <span class="bottom-bar-sep">|</span>
          <span class="bottom-bar-detail">Sensors: {selectedDetails.data.sensor_count}</span>
          {#if selectedDetails.data.attributes_summary?.length > 0}
            <span class="bottom-bar-sep">|</span>
            {#each selectedDetails.data.attributes_summary as attr}
              <span class="bottom-bar-tag">{attr.type}: {attr.count}</span>
            {/each}
          {/if}
        {:else if selectedDetails.type === "sensor"}
          <span class="bottom-bar-detail">ID: {selectedDetails.data.sensor_id}</span>
          <span class="bottom-bar-sep">|</span>
          <span class="bottom-bar-detail">Connector: {selectedDetails.data.connector_name}</span>
          <span class="bottom-bar-sep">|</span>
          <span class="bottom-bar-detail">Attrs: {Object.keys(selectedDetails.data.attributes || {}).length}</span>
        {:else if selectedDetails.type === "attribute"}
          <span class="bottom-bar-detail">ID: {selectedDetails.data.attribute_id}</span>
          <span class="bottom-bar-sep">|</span>
          <span class="bottom-bar-detail">Type: {selectedDetails.data.attribute_type}</span>
          <span class="bottom-bar-sep">|</span>
          <span class="bottom-bar-detail">Sensor: {selectedDetails.data.sensor_id}</span>
          <span class="bottom-bar-sep">|</span>
          <span class="bottom-bar-value">{formatAttributeValue(selectedDetails.data)}</span>
        {:else if selectedDetails.type === "room"}
          <span class="bottom-bar-detail">ID: {selectedDetails.data.id}</span>
          <span class="bottom-bar-sep">|</span>
          <span class="bottom-bar-detail">Sensors: {selectedDetails.data.sensor_count}</span>
        {/if}
      </div>

      <button onclick={() => { selectedNode = null; selectedDetails = null; highlightedNodes = new Set(); sigma?.refresh(); }} class="bottom-bar-close" title="Close">
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
        </svg>
      </button>
    </div>
  {/if}

  <!-- Stats -->
  <div class="stats">
    <span>Nodes: {graph?.order || 0}</span>
    <span>Edges: {graph?.size || 0}</span>
    <span>Scale: {(scaledNodeSizes.sensor / baseNodeSizes.sensor).toFixed(2)}x</span>
  </div>
</div>

<style>
  .lobby-graph {
    position: relative;
    width: 100%;
    height: 100%;
    min-height: 100vh;
    background: linear-gradient(135deg, #0f172a 0%, #1e293b 100%);
  }

  .lobby-graph.fullscreen {
    position: fixed;
    inset: 0;
    z-index: 9999;
    min-height: unset;
  }

  .graph-container {
    position: absolute;
    inset: 0;
  }

  .glow-overlay {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    pointer-events: none;
    z-index: 1;
  }

  .controls {
    position: absolute;
    top: 1rem;
    right: 1rem;
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
    z-index: 10;
  }

  .control-divider {
    width: 100%;
    height: 1px;
    background: rgba(75, 85, 99, 0.4);
  }

  .control-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 2.5rem;
    height: 2.5rem;
    background: rgba(31, 41, 55, 0.9);
    border: 1px solid rgba(75, 85, 99, 0.5);
    border-radius: 0.5rem;
    color: #d1d5db;
    cursor: pointer;
    transition: all 0.15s ease;
  }

  .control-btn:hover:not(:disabled) {
    background: rgba(55, 65, 81, 0.9);
    color: #ffffff;
  }

  .control-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .legend {
    position: absolute;
    bottom: 1rem;
    left: 1rem;
    display: flex;
    gap: 1rem;
    padding: 0.75rem 1rem;
    background: rgba(31, 41, 55, 0.9);
    border: 1px solid rgba(75, 85, 99, 0.5);
    border-radius: 0.5rem;
    z-index: 10;
  }

  .legend-item {
    display: flex;
    align-items: center;
    gap: 0.375rem;
    font-size: 0.75rem;
    color: #d1d5db;
  }

  .legend-dot {
    width: 10px;
    height: 10px;
    border-radius: 50%;
  }

  /* Compact hover tooltip - follows cursor */
  .hover-tooltip {
    position: fixed;
    display: flex;
    align-items: center;
    gap: 0.375rem;
    padding: 0.375rem 0.625rem;
    background: rgba(17, 24, 39, 0.95);
    border: 1px solid rgba(75, 85, 99, 0.6);
    border-radius: 0.375rem;
    z-index: 30;
    pointer-events: none;
    white-space: nowrap;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.4);
  }

  .hover-icon {
    font-size: 0.8rem;
  }

  .hover-label {
    font-size: 0.75rem;
    font-weight: 600;
    color: #f3f4f6;
  }

  .hover-meta {
    font-size: 0.7rem;
    color: #9ca3af;
  }

  /* Selected node bottom bar */
  .bottom-bar {
    position: absolute;
    bottom: 3.5rem;
    left: 50%;
    transform: translateX(-50%);
    display: flex;
    align-items: center;
    gap: 0.5rem;
    max-width: calc(100% - 2rem);
    padding: 0.5rem 0.75rem;
    background: rgba(17, 24, 39, 0.95);
    border: 1px solid rgba(75, 85, 99, 0.5);
    border-radius: 0.5rem;
    z-index: 20;
    box-shadow: 0 -4px 16px rgba(0, 0, 0, 0.3);
  }

  .bottom-bar-main {
    display: flex;
    align-items: center;
    gap: 0.375rem;
    overflow-x: auto;
    white-space: nowrap;
    scrollbar-width: none;
  }

  .bottom-bar-main::-webkit-scrollbar {
    display: none;
  }

  .bottom-bar-icon {
    font-size: 0.9rem;
    flex-shrink: 0;
  }

  .bottom-bar-type {
    font-size: 0.65rem;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    color: #6b7280;
    flex-shrink: 0;
  }

  .bottom-bar-label {
    font-size: 0.8rem;
    font-weight: 600;
    color: #f3f4f6;
    flex-shrink: 0;
  }

  .bottom-bar-sep {
    color: #374151;
    font-size: 0.7rem;
    flex-shrink: 0;
  }

  .bottom-bar-detail {
    font-size: 0.75rem;
    color: #d1d5db;
    flex-shrink: 0;
  }

  .bottom-bar-tag {
    font-size: 0.65rem;
    padding: 0.125rem 0.375rem;
    background: rgba(75, 85, 99, 0.4);
    border-radius: 0.25rem;
    color: #d1d5db;
    flex-shrink: 0;
  }

  .bottom-bar-value {
    font-size: 0.7rem;
    font-family: monospace;
    color: #a5f3fc;
    max-width: 200px;
    overflow: hidden;
    text-overflow: ellipsis;
    flex-shrink: 0;
  }

  .bottom-bar-close {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 1.25rem;
    height: 1.25rem;
    background: rgba(55, 65, 81, 0.5);
    border: none;
    border-radius: 0.25rem;
    color: #9ca3af;
    cursor: pointer;
    flex-shrink: 0;
  }

  .bottom-bar-close:hover {
    background: rgba(75, 85, 99, 0.5);
    color: #d1d5db;
  }

  .stats {
    position: absolute;
    bottom: 1rem;
    right: 1rem;
    display: flex;
    gap: 1rem;
    padding: 0.5rem 0.75rem;
    background: rgba(31, 41, 55, 0.9);
    border: 1px solid rgba(75, 85, 99, 0.5);
    border-radius: 0.5rem;
    font-size: 0.7rem;
    color: #9ca3af;
    z-index: 10;
  }

  /* Export modal */
  .export-overlay {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.6);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 10000;
    backdrop-filter: blur(4px);
  }

  .export-modal {
    background: #1f2937;
    border: 1px solid rgba(75, 85, 99, 0.6);
    border-radius: 0.75rem;
    width: 22rem;
    box-shadow: 0 20px 60px rgba(0, 0, 0, 0.5);
  }

  .export-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 1rem 1.25rem;
    border-bottom: 1px solid rgba(75, 85, 99, 0.3);
  }

  .export-title {
    font-size: 0.95rem;
    font-weight: 600;
    color: #f3f4f6;
  }

  .export-close {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 1.5rem;
    height: 1.5rem;
    background: none;
    border: none;
    color: #9ca3af;
    cursor: pointer;
    border-radius: 0.25rem;
  }

  .export-close:hover {
    background: rgba(75, 85, 99, 0.4);
    color: #d1d5db;
  }

  .export-body {
    padding: 1.25rem;
    display: flex;
    flex-direction: column;
    gap: 1.25rem;
  }

  .export-field {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
  }

  .export-label {
    font-size: 0.75rem;
    font-weight: 500;
    color: #9ca3af;
    text-transform: uppercase;
    letter-spacing: 0.04em;
  }

  .export-options {
    display: flex;
    gap: 0.375rem;
  }

  .export-option {
    flex: 1;
    padding: 0.5rem 0.75rem;
    background: rgba(31, 41, 55, 0.8);
    border: 1px solid rgba(75, 85, 99, 0.4);
    border-radius: 0.375rem;
    color: #d1d5db;
    font-size: 0.8rem;
    font-weight: 500;
    cursor: pointer;
    transition: all 0.15s;
    text-align: center;
  }

  .export-option:hover {
    background: rgba(55, 65, 81, 0.6);
    border-color: rgba(107, 114, 128, 0.6);
  }

  .export-option.active {
    background: rgba(6, 182, 212, 0.15);
    border-color: rgba(6, 182, 212, 0.5);
    color: #22d3ee;
  }

  .export-hint {
    font-size: 0.7rem;
    color: #6b7280;
  }

  .export-warn {
    color: #f59e0b;
  }

  .export-footer {
    display: flex;
    gap: 0.5rem;
    padding: 1rem 1.25rem;
    border-top: 1px solid rgba(75, 85, 99, 0.3);
    justify-content: flex-end;
  }

  .export-cancel {
    padding: 0.5rem 1rem;
    background: none;
    border: 1px solid rgba(75, 85, 99, 0.4);
    border-radius: 0.375rem;
    color: #9ca3af;
    font-size: 0.8rem;
    cursor: pointer;
  }

  .export-cancel:hover {
    background: rgba(55, 65, 81, 0.4);
    color: #d1d5db;
  }

  .export-submit {
    padding: 0.5rem 1.25rem;
    background: #0891b2;
    border: none;
    border-radius: 0.375rem;
    color: white;
    font-size: 0.8rem;
    font-weight: 500;
    cursor: pointer;
    transition: background 0.15s;
  }

  .export-submit:hover:not(:disabled) {
    background: #06b6d4;
  }

  .export-submit:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  /* Recording */
  .control-btn.recording {
    background: rgba(220, 38, 38, 0.3);
    border-color: rgba(239, 68, 68, 0.6);
    color: #fca5a5;
  }

  .control-btn.recording:hover {
    background: rgba(220, 38, 38, 0.5);
    border-color: rgba(239, 68, 68, 0.8);
  }

  .control-btn.sound-active {
    background: rgba(16, 185, 129, 0.2);
    border-color: rgba(52, 211, 153, 0.5);
    color: #6ee7b7;
  }

  .control-btn.sound-active:hover {
    background: rgba(16, 185, 129, 0.35);
    border-color: rgba(52, 211, 153, 0.7);
  }

  .recording-indicator {
    position: absolute;
    top: 1rem;
    left: 1rem;
    display: flex;
    align-items: center;
    gap: 0.5rem;
    padding: 0.4rem 0.75rem;
    background: rgba(31, 41, 55, 0.9);
    border: 1px solid rgba(239, 68, 68, 0.5);
    border-radius: 0.5rem;
    z-index: 10;
    font-size: 0.75rem;
    font-weight: 600;
  }

  .rec-dot {
    width: 0.5rem;
    height: 0.5rem;
    border-radius: 50%;
    background: #ef4444;
    animation: rec-blink 1s ease-in-out infinite;
  }

  .rec-label {
    color: #ef4444;
    letter-spacing: 0.08em;
  }

  .rec-time {
    color: #d1d5db;
    font-variant-numeric: tabular-nums;
  }

  @keyframes rec-blink {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.3; }
  }

  @keyframes spin {
    from { transform: rotate(0deg); }
    to { transform: rotate(360deg); }
  }

  .animate-spin {
    animation: spin 1s linear infinite;
  }
</style>
