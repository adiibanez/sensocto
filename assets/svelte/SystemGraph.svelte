<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import Graph from "graphology";
  import Sigma from "sigma";
  import forceAtlas2 from "graphology-layout-forceatlas2";

  type GraphMode = "system_load" | "backpressure" | "attention" | "battery";

  interface SystemLoadData {
    cpu: number;
    memory: number;
    pubsub: number;
    queues: number;
    load_level: string;
  }

  interface BackpressureSocket {
    id: string;
    quality: string;
    sensor_count: number;
  }

  interface AttentionSensor {
    id: string;
    level: string;
  }

  interface BatterySensor {
    id: string;
    status: string;
  }

  interface Props {
    mode: GraphMode;
    data: any;
  }

  let { mode, data = {} }: Props = $props();

  let container: HTMLDivElement;
  let graph: Graph | null = null;
  let sigma: Sigma | null = null;
  let lastMode: GraphMode | null = null;
  let lastNodeCount = 0;

  function pressureColor(value: number): string {
    if (value >= 0.85) return "#ef4444";
    if (value >= 0.70) return "#f97316";
    if (value >= 0.50) return "#eab308";
    return "#22c55e";
  }

  function pressureSize(value: number, min: number, max: number): number {
    return min + value * (max - min);
  }

  function loadLevelColor(level: string): string {
    switch (level) {
      case "critical": return "#ef4444";
      case "high": return "#f97316";
      case "elevated": return "#eab308";
      default: return "#6b7280";
    }
  }

  function qualityColor(quality: string): string {
    switch (quality) {
      case "high": return "#22c55e";
      case "medium": return "#3b82f6";
      case "low": return "#eab308";
      case "minimal": return "#f97316";
      case "paused": return "#ef4444";
      default: return "#6b7280";
    }
  }

  function attentionColor(level: string): string {
    switch (level) {
      case "high": return "#22c55e";
      case "medium": return "#eab308";
      case "low": return "#f97316";
      default: return "#4b5563";
    }
  }

  function batteryColor(status: string): string {
    switch (status) {
      case "critical": return "#ef4444";
      case "low": return "#eab308";
      default: return "#22c55e";
    }
  }

  // Add invisible bounding nodes to control camera viewport
  function addBounds(g: Graph, extent: number) {
    g.addNode("__bound_tl", { x: -extent, y: -extent, size: 0.5, color: "rgba(0,0,0,0)", hidden: true });
    g.addNode("__bound_br", { x: extent, y: extent, size: 0.5, color: "rgba(0,0,0,0)", hidden: true });
  }

  // ── Graph Builders ──────────────────────────────────────────

  function buildSystemLoadGraph(d: SystemLoadData) {
    const g = new Graph();

    g.addNode("hub", {
      x: 0, y: 0,
      size: 12,
      color: loadLevelColor(d.load_level),
      label: ""
    });

    const metrics = [
      { id: "cpu", value: d.cpu, angle: -Math.PI / 4 },
      { id: "memory", value: d.memory, angle: Math.PI / 4 },
      { id: "pubsub", value: d.pubsub, angle: (3 * Math.PI) / 4 },
      { id: "queues", value: d.queues, angle: -(3 * Math.PI) / 4 }
    ];

    const radius = 80;
    for (const m of metrics) {
      g.addNode(m.id, {
        x: Math.cos(m.angle) * radius,
        y: Math.sin(m.angle) * radius,
        size: pressureSize(m.value, 5, 16),
        color: pressureColor(m.value),
        label: ""
      });
      g.addEdge("hub", m.id, {
        size: 1 + m.value * 2,
        color: `rgba(107, 114, 128, ${0.2 + m.value * 0.4})`
      });
    }

    addBounds(g, 120);
    return g;
  }

  function buildBackpressureGraph(d: { sockets: BackpressureSocket[] }) {
    const g = new Graph();
    const sockets = d.sockets || [];

    if (sockets.length === 0) {
      g.addNode("empty", { x: 0, y: 0, size: 8, color: "#4b5563", label: "" });
      addBounds(g, 80);
      return g;
    }

    if (sockets.length === 1) {
      const s = sockets[0];
      g.addNode(s.id, {
        x: 0, y: 0,
        size: Math.min(10 + Math.sqrt(s.sensor_count), 24),
        color: qualityColor(s.quality),
        label: ""
      });
      addBounds(g, 80);
      return g;
    }

    const angleStep = (2 * Math.PI) / sockets.length;
    const radius = 60;
    for (let i = 0; i < sockets.length; i++) {
      const s = sockets[i];
      g.addNode(s.id, {
        x: Math.cos(i * angleStep) * radius,
        y: Math.sin(i * angleStep) * radius,
        size: Math.min(8 + Math.sqrt(s.sensor_count), 20),
        color: qualityColor(s.quality),
        label: ""
      });
    }

    addBounds(g, 100);
    return g;
  }

  function buildAttentionGraph(d: { sensors: AttentionSensor[] }) {
    const g = new Graph();
    const sensors = (d.sensors || []).slice(0, 200);

    if (sensors.length === 0) {
      g.addNode("empty", { x: 0, y: 0, size: 6, color: "#4b5563", label: "" });
      addBounds(g, 80);
      return g;
    }

    const ringRadii: Record<string, number> = { high: 20, medium: 50, low: 80, none: 110 };
    const ringSizes: Record<string, number> = { high: 6, medium: 5, low: 4, none: 3 };
    const grouped: Record<string, AttentionSensor[]> = { high: [], medium: [], low: [], none: [] };
    for (const s of sensors) {
      const level = s.level in grouped ? s.level : "none";
      grouped[level].push(s);
    }

    for (const [level, items] of Object.entries(grouped)) {
      const r = ringRadii[level];
      const nodeSize = ringSizes[level];
      const count = items.length;
      if (count === 0) continue;

      const angleStep = (2 * Math.PI) / count;
      for (let i = 0; i < count; i++) {
        const nodeId = items[i].id;
        if (g.hasNode(nodeId)) continue;
        const jitter = (Math.random() - 0.5) * 8;
        g.addNode(nodeId, {
          x: Math.cos(i * angleStep + Math.random() * 0.2) * (r + jitter),
          y: Math.sin(i * angleStep + Math.random() * 0.2) * (r + jitter),
          size: nodeSize,
          color: attentionColor(level),
          label: ""
        });
      }
    }

    addBounds(g, 140);
    return g;
  }

  function buildBatteryGraph(d: { sensors: BatterySensor[] }) {
    const g = new Graph();
    const sensors = (d.sensors || []).slice(0, 200);

    if (sensors.length === 0) {
      g.addNode("empty", { x: 0, y: 0, size: 6, color: "#4b5563", label: "" });
      addBounds(g, 80);
      return g;
    }

    const clusterCenters: Record<string, { x: number; y: number }> = {
      normal: { x: -80, y: 0 },
      low: { x: 0, y: 0 },
      critical: { x: 80, y: 0 }
    };

    for (const s of sensors) {
      if (g.hasNode(s.id)) continue;
      const status = s.status in clusterCenters ? s.status : "normal";
      const center = clusterCenters[status];
      const jx = (Math.random() - 0.5) * 50;
      const jy = (Math.random() - 0.5) * 50;
      g.addNode(s.id, {
        x: center.x + jx,
        y: center.y + jy,
        size: status === "critical" ? 6 : 4,
        color: batteryColor(status),
        label: ""
      });
    }

    if (sensors.length > 3) {
      forceAtlas2.assign(g, {
        iterations: 40,
        settings: {
          gravity: 1,
          scalingRatio: 10,
          barnesHutOptimize: sensors.length > 50,
          strongGravityMode: true
        }
      });
    }

    addBounds(g, 160);
    return g;
  }

  // ── Update (mutate existing nodes) ──────────────────────────

  function updateSystemLoadNodes(d: SystemLoadData) {
    if (!graph) return;
    if (graph.hasNode("hub")) {
      graph.setNodeAttribute("hub", "color", loadLevelColor(d.load_level));
    }
    const metrics = [
      { id: "cpu", value: d.cpu },
      { id: "memory", value: d.memory },
      { id: "pubsub", value: d.pubsub },
      { id: "queues", value: d.queues }
    ];
    for (const m of metrics) {
      if (graph.hasNode(m.id)) {
        graph.setNodeAttribute(m.id, "size", pressureSize(m.value, 5, 16));
        graph.setNodeAttribute(m.id, "color", pressureColor(m.value));
      }
      const edgeId = graph.edge("hub", m.id);
      if (edgeId) {
        graph.setEdgeAttribute(edgeId, "size", 1 + m.value * 2);
        graph.setEdgeAttribute(edgeId, "color", `rgba(107, 114, 128, ${0.2 + m.value * 0.4})`);
      }
    }
  }

  // ── Init / Rebuild ──────────────────────────────────────────

  function buildGraph(): Graph {
    switch (mode) {
      case "system_load": return buildSystemLoadGraph(data as SystemLoadData);
      case "backpressure": return buildBackpressureGraph(data as { sockets: BackpressureSocket[] });
      case "attention": return buildAttentionGraph(data as { sensors: AttentionSensor[] });
      case "battery": return buildBatteryGraph(data as { sensors: BatterySensor[] });
      default: return new Graph();
    }
  }

  function nodeCount(): number {
    if (!data) return 0;
    switch (mode) {
      case "system_load": return 5;
      case "backpressure": return (data as any)?.sockets?.length || 0;
      case "attention": return (data as any)?.sensors?.length || 0;
      case "battery": return (data as any)?.sensors?.length || 0;
      default: return 0;
    }
  }

  function initSigma() {
    if (!container) return;
    cleanup();

    graph = buildGraph();
    lastMode = mode;
    lastNodeCount = nodeCount();

    sigma = new Sigma(graph, container, {
      renderLabels: false,
      defaultNodeColor: "#6b7280",
      defaultEdgeColor: "rgba(55, 65, 81, 0.25)",
      defaultEdgeType: "line",
      allowInvalidContainer: true,
      minCameraRatio: 0.5,
      maxCameraRatio: 2,
      stagePadding: 30,
      labelFont: "Inter, system-ui, sans-serif",
      autoRescale: true,
    });

    sigma.getCamera().disable();
  }

  function cleanup() {
    if (sigma) {
      sigma.kill();
      sigma = null;
    }
    if (graph) {
      graph.clear();
      graph = null;
    }
  }

  // ── Lifecycle ───────────────────────────────────────────────

  onMount(() => {
    if (data && Object.keys(data).length > 0) {
      initSigma();
    }
  });

  onDestroy(() => {
    cleanup();
  });

  $effect(() => {
    if (!container) return;
    const _mode = mode;
    const _data = data;

    if (!_data || Object.keys(_data).length === 0) return;

    if (!sigma || _mode !== lastMode) {
      initSigma();
      return;
    }

    const currentCount = nodeCount();
    if (currentCount !== lastNodeCount) {
      initSigma();
      return;
    }

    if (_mode === "system_load") {
      updateSystemLoadNodes(_data as SystemLoadData);
      sigma.refresh();
    } else {
      initSigma();
    }
  });
</script>

<div
  bind:this={container}
  class="system-graph-container"
></div>

<style>
  .system-graph-container {
    width: 100%;
    height: 100%;
    background: rgba(17, 24, 39, 0.5);
    border-radius: 0.5rem;
    overflow: hidden;
  }

  .system-graph-container :global(canvas) {
    border-radius: 0.5rem;
  }
</style>
