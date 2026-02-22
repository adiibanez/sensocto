<script lang="ts">
  import { onMount, onDestroy } from "svelte";

  interface User {
    connector_id: string;
    connector_name: string;
    sensor_count: number;
    sensors: Array<{ sensor_id: string; sensor_name: string }>;
  }

  interface Attribute {
    attribute_id: string;
    attribute_type: string;
    lastvalue?: { payload: any; timestamp: number };
  }

  interface Sensor {
    sensor_id: string;
    sensor_name: string;
    connector_id: string;
    connector_name: string;
    attributes: Record<string, Attribute>;
    attention_level?: string;
  }

  let {
    rooms = [],
    users = [],
    sensors = {},
  }: {
    rooms: any[];
    users: User[];
    sensors: Record<string, Sensor>;
  } = $props();

  let container: HTMLDivElement;
  let outerContainer: HTMLDivElement;
  let graph: any = null;
  let ready = $state(false);
  let isFullscreen = $state(false);

  const COLORS = {
    room: "#4ade80",
    user: "#3b82f6",
    sensor: "#f97316",
    attribute: "#a855f7",
    sensorActive: "#ef4444",
    edge: "#334155",
    background: "#0f172a",
  };

  const ATTR_COLORS: Record<string, string> = {
    heartrate: "#ef4444",
    hr: "#ef4444",
    ecg: "#22c55e",
    battery: "#eab308",
    temperature: "#f97316",
    imu: "#06b6d4",
    eye_gaze: "#8b5cf6",
    eye_aperture: "#a855f7",
    eye_blink: "#c084fc",
    respiration: "#14b8a6",
    hrv: "#ec4899",
    geolocation: "#3b82f6",
    skeleton: "#f59e0b",
    quaternion: "#6366f1",
    accelerometer: "#0ea5e9",
  };

  let activeNodes: Map<string, number> = new Map();
  const GLOW_DURATION = 600;

  interface GraphNode {
    id: string;
    name: string;
    type: "room" | "user" | "sensor" | "attribute";
    color: string;
    val: number;
    sensorId?: string;
    attrType?: string;
    fx?: number;
    fy?: number;
    fz?: number;
    x?: number;
    y?: number;
    z?: number;
  }

  interface GraphLink {
    source: string;
    target: string;
    color: string;
  }

  function buildGraphData(): { nodes: GraphNode[]; links: GraphLink[] } {
    const nodes: GraphNode[] = [];
    const links: GraphLink[] = [];
    const nodeIds = new Set<string>();

    users.forEach((user) => {
      const userId = `user:${user.connector_id}`;
      if (!nodeIds.has(userId)) {
        nodes.push({
          id: userId,
          name: user.connector_name || user.connector_id,
          type: "user",
          color: COLORS.user,
          val: 8 + Math.min(user.sensor_count * 2, 20),
        });
        nodeIds.add(userId);
      }

      user.sensors.forEach((s) => {
        const sensorId = `sensor:${s.sensor_id}`;
        if (!nodeIds.has(sensorId)) {
          const sensorData = sensors[s.sensor_id];
          const attrCount = sensorData
            ? Object.keys(sensorData.attributes || {}).length
            : 0;

          nodes.push({
            id: sensorId,
            name: s.sensor_name || s.sensor_id,
            type: "sensor",
            color: COLORS.sensor,
            val: 4 + Math.min(attrCount, 8),
            sensorId: s.sensor_id,
          });
          nodeIds.add(sensorId);

          links.push({
            source: userId,
            target: sensorId,
            color: COLORS.edge,
          });

          if (sensorData?.attributes) {
            Object.entries(sensorData.attributes).forEach(([attrId, attr]) => {
              const attrNodeId = `attr:${s.sensor_id}:${attrId}`;
              if (!nodeIds.has(attrNodeId)) {
                const attrType = (attr as Attribute).attribute_type || attrId;
                nodes.push({
                  id: attrNodeId,
                  name: attrId,
                  type: "attribute",
                  color:
                    ATTR_COLORS[attrType] ||
                    ATTR_COLORS[attrId] ||
                    COLORS.attribute,
                  val: 2,
                  sensorId: s.sensor_id,
                  attrType: attrType,
                });
                nodeIds.add(attrNodeId);

                links.push({
                  source: sensorId,
                  target: attrNodeId,
                  color: `${COLORS.edge}88`,
                });
              }
            });
          }
        }
      });
    });

    return { nodes, links };
  }

  function getNodeColor(node: GraphNode): string {
    const glowTime = activeNodes.get(node.id);
    if (glowTime) {
      const elapsed = Date.now() - glowTime;
      if (elapsed < GLOW_DURATION) {
        const intensity = 1 - elapsed / GLOW_DURATION;
        if (intensity > 0.5) return "#ffffff";
        if (intensity > 0.2) return COLORS.sensorActive;
      } else {
        activeNodes.delete(node.id);
      }
    }
    return node.color;
  }

  function initGraph(ForceGraph3D: any) {
    if (!container) return;

    const data = buildGraphData();

    graph = ForceGraph3D({ controlType: "orbit" })(container)
      .graphData(data)
      .backgroundColor(COLORS.background)
      .nodeLabel((node: GraphNode) => {
        const typeLabel = node.type.charAt(0).toUpperCase() + node.type.slice(1);
        return `<div style="background:rgba(15,23,42,0.9);color:#e2e8f0;padding:4px 8px;border-radius:4px;font-size:11px;border:1px solid ${node.color}40">
          <strong style="color:${node.color}">${typeLabel}</strong>: ${node.name}
        </div>`;
      })
      .nodeColor((node: GraphNode) => getNodeColor(node))
      .nodeVal((node: GraphNode) => node.val)
      .nodeOpacity(0.9)
      .nodeResolution(12)
      .linkColor((link: GraphLink) => link.color)
      .linkWidth(0.5)
      .linkOpacity(0.4)
      .linkDirectionalParticles(0)
      .d3AlphaDecay(0.03)
      .d3VelocityDecay(0.4)
      .warmupTicks(100)
      .cooldownTicks(200)
      .onNodeClick((node: GraphNode) => {
        if (graph) {
          const distance = 120;
          const distRatio =
            1 + distance / Math.hypot(node.x || 0, node.y || 0, node.z || 0);
          graph.cameraPosition(
            {
              x: (node.x || 0) * distRatio,
              y: (node.y || 0) * distRatio,
              z: (node.z || 0) * distRatio,
            },
            node,
            1000
          );
        }
      })
      .onNodeHover((node: GraphNode | null) => {
        if (container) {
          container.style.cursor = node ? "pointer" : "default";
        }
      });

    graph
      .d3Force("charge")
      ?.strength((node: GraphNode) => {
        switch (node.type) {
          case "user":
            return -15;
          case "sensor":
            return -5;
          case "attribute":
            return -2;
          default:
            return -5;
        }
      });

    graph.d3Force("link")?.distance((link: any) => {
      const src =
        typeof link.source === "object" ? link.source : { type: "unknown" };
      if (src.type === "user") return 12;
      if (src.type === "sensor") return 5;
      return 8;
    });

    graph.d3Force("center")?.strength(0.3);

    ready = true;
  }

  function updateGraphData() {
    if (!graph) return;
    const data = buildGraphData();
    graph.graphData(data);
  }

  function nudgeNode(nodeId: string) {
    if (!graph) return;
    const data = graph.graphData();
    const node = data.nodes.find((n: GraphNode) => n.id === nodeId);
    if (!node || node.fx != null) return;
    const jitter = 3;
    node.vx = (node.vx || 0) + (Math.random() - 0.5) * jitter;
    node.vy = (node.vy || 0) + (Math.random() - 0.5) * jitter;
    node.vz = (node.vz || 0) + (Math.random() - 0.5) * jitter;
    graph.d3ReheatSimulation();
  }

  function handleActivity(e: Event) {
    const detail = (e as CustomEvent).detail;
    const sensorId = detail?.sensor_id;
    if (!sensorId) return;

    const now = Date.now();
    activeNodes.set(`sensor:${sensorId}`, now);
    nudgeNode(`sensor:${sensorId}`);

    const attrIds = detail?.attribute_ids;
    if (Array.isArray(attrIds)) {
      attrIds.forEach((attrId: string) => {
        activeNodes.set(`attr:${sensorId}:${attrId}`, now);
        nudgeNode(`attr:${sensorId}:${attrId}`);
      });
    }
  }

  let colorRefreshTimer: ReturnType<typeof setInterval> | null = null;
  let prevTopologyKey = "";

  function getTopologyKey(): string {
    const sensorIds = Object.keys(sensors).sort().join(",");
    const userIds = users.map((u) => u.connector_id).sort().join(",");
    return `${userIds}|${sensorIds}`;
  }

  onMount(() => {
    // Load 3d-force-graph lazily via a script tag to avoid crashing the Svelte module
    const script = document.createElement("script");
    script.type = "module";
    script.textContent = `
      import ForceGraph3D from "https://cdn.jsdelivr.net/npm/3d-force-graph@1/+esm";
      window.__ForceGraph3D = ForceGraph3D;
      window.dispatchEvent(new CustomEvent("force-graph-3d-loaded"));
    `;

    const onLoaded = () => {
      window.removeEventListener("force-graph-3d-loaded", onLoaded);
      const factory = (window as any).__ForceGraph3D;
      if (factory) {
        initGraph(factory);
      }
    };

    window.addEventListener("force-graph-3d-loaded", onLoaded);
    document.head.appendChild(script);

    prevTopologyKey = getTopologyKey();

    window.addEventListener("graph-activity-event", handleActivity);

    colorRefreshTimer = setInterval(() => {
      if (graph && activeNodes.size > 0) {
        graph.nodeColor(graph.nodeColor());
      }
    }, 100);
  });

  $effect(() => {
    const key = getTopologyKey();
    if (key !== prevTopologyKey && graph) {
      prevTopologyKey = key;
      updateGraphData();
    }
  });

  onDestroy(() => {
    window.removeEventListener("graph-activity-event", handleActivity);
    if (colorRefreshTimer) clearInterval(colorRefreshTimer);
    if (graph) {
      graph._destructor?.();
      graph = null;
    }
  });

  function toggleFullscreen() {
    if (!outerContainer) return;
    if (!document.fullscreenElement) {
      outerContainer.requestFullscreen();
    } else {
      document.exitFullscreen();
    }
  }

  function handleFullscreenChange() {
    isFullscreen = !!document.fullscreenElement;
    setTimeout(() => handleResize(), 50);
  }

  function handleResize() {
    if (graph && container) {
      graph.width(container.clientWidth);
      graph.height(container.clientHeight);
    }
  }
</script>

<svelte:window onresize={handleResize} />
<svelte:document onfullscreenchange={handleFullscreenChange} />

<div class="graph3d-container" class:fullscreen={isFullscreen} bind:this={outerContainer}>
  <div class="graph3d-header">
    <h2>3D Graph</h2>
    <span class="stat">
      {users.length} users · {Object.keys(sensors).length} sensors
    </span>
    <div class="controls">
      <button
        class="control-btn"
        title="Reset camera"
        onclick={() => {
          if (graph)
            graph.cameraPosition({ x: 0, y: 0, z: 300 }, { x: 0, y: 0, z: 0 }, 1000);
        }}
      >
        Reset
      </button>
      <button
        class="control-btn"
        title="Zoom to fit"
        onclick={() => {
          if (graph) graph.zoomToFit(1000, 50);
        }}
      >
        Fit
      </button>
      <button
        class="control-btn"
        title={isFullscreen ? "Exit fullscreen" : "Fullscreen"}
        onclick={toggleFullscreen}
      >
        {isFullscreen ? "Exit FS" : "Fullscreen"}
      </button>
    </div>
  </div>
  <div class="graph3d-canvas" bind:this={container}>
    {#if !ready}
      <div class="loading">Loading 3D engine...</div>
    {/if}
  </div>
  <div class="graph3d-legend">
    <span class="legend-item">
      <span class="dot" style="background:{COLORS.user}"></span> User
    </span>
    <span class="legend-item">
      <span class="dot" style="background:{COLORS.sensor}"></span> Sensor
    </span>
    <span class="legend-item">
      <span class="dot" style="background:{COLORS.attribute}"></span> Attribute
    </span>
  </div>
</div>

<style>
  .graph3d-container {
    background: #0f172a;
    border-radius: 0.5rem;
    border: 1px solid rgba(59, 130, 246, 0.3);
    overflow: hidden;
    display: flex;
    flex-direction: column;
    height: 100%;
  }

  .graph3d-container.fullscreen {
    border-radius: 0;
    border: none;
  }

  .graph3d-header {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    padding: 0.4rem 0.75rem;
    background: rgba(59, 130, 246, 0.08);
    border-bottom: 1px solid rgba(59, 130, 246, 0.2);
  }

  .graph3d-header h2 {
    font-size: 0.75rem;
    font-weight: 600;
    color: #60a5fa;
    margin: 0;
    font-family: monospace;
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  .stat {
    font-size: 0.65rem;
    color: #60a5fa;
    font-family: monospace;
    opacity: 0.7;
  }

  .controls {
    margin-left: auto;
    display: flex;
    gap: 0.25rem;
  }

  .control-btn {
    padding: 0.2rem 0.5rem;
    font-size: 0.7rem;
    font-family: monospace;
    background: rgba(59, 130, 246, 0.15);
    border: 1px solid rgba(59, 130, 246, 0.3);
    border-radius: 0.25rem;
    color: #93c5fd;
    cursor: pointer;
    transition: all 0.15s ease;
  }

  .control-btn:hover {
    background: rgba(59, 130, 246, 0.3);
    color: #bfdbfe;
  }

  .graph3d-canvas {
    flex: 1;
    min-height: 0;
    position: relative;
  }

  .graph3d-canvas :global(canvas) {
    width: 100% !important;
    height: 100% !important;
  }

  .loading {
    position: absolute;
    inset: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    color: #60a5fa;
    font-family: monospace;
    font-size: 0.85rem;
    opacity: 0.7;
  }

  .graph3d-legend {
    display: flex;
    gap: 1rem;
    padding: 0.3rem 0.75rem;
    background: rgba(15, 23, 42, 0.8);
    border-top: 1px solid rgba(59, 130, 246, 0.15);
    justify-content: center;
  }

  .legend-item {
    display: flex;
    align-items: center;
    gap: 0.3rem;
    font-size: 0.65rem;
    color: #94a3b8;
    font-family: monospace;
  }

  .dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    display: inline-block;
  }
</style>
