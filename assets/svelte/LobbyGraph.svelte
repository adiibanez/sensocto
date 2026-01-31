<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import Graph from "graphology";
  import Sigma from "sigma";
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
  let nodeDetails = $state<any>(null);
  let isLayoutRunning = $state(false);

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
    room: 20,
    user: 15,
    sensor: 10,
    attribute: 6
  };

  // Current scaled sizes (updated when graph is built)
  let scaledNodeSizes = { ...baseNodeSizes };

  // Calculate scale factor based on total node count
  // Small graphs (<100 nodes) get larger nodes, large graphs (>500) get smaller nodes
  function calculateNodeScale(nodeCount: number): number {
    if (nodeCount <= 50) {
      // Very small graph: scale up by 1.5x
      return 1.5;
    } else if (nodeCount <= 100) {
      // Small graph: scale up by 1.25x
      return 1.25;
    } else if (nodeCount <= 300) {
      // Medium graph: normal size
      return 1.0;
    } else if (nodeCount <= 700) {
      // Large graph: scale down to 0.7x
      return 0.7;
    } else if (nodeCount <= 1500) {
      // Very large graph: scale down to 0.5x
      return 0.5;
    } else {
      // Massive graph: scale down to 0.35x
      return 0.35;
    }
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
        size: scaledNodeSizes.room,
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
        size: scaledNodeSizes.user + Math.min(user.sensor_count * scale, 10 * scale),
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
        size: scaledNodeSizes.sensor + Math.min(attrCount * 2 * scale, 8 * scale),
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
          size: Math.max(0.5, 1 * scale),
          color: "#4b5563"
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
          size: scaledNodeSizes.attribute,
          color: attrColor,
          nodeType: "attribute",
          data: { ...attr, sensor_id: sensorId },
          x: Math.random() * 100,
          y: Math.random() * 100
        });

        graph.addEdge(sensorNodeId, attrNodeId, {
          size: Math.max(0.25, 0.5 * scale),
          color: "#374151"
        });
      }
    }

    // Connect rooms to sensors if we have room data with sensor connections
    // (This would require additional data from the backend)
  }

  function runLayout() {
    if (!graph || graph.order === 0) return;

    isLayoutRunning = true;

    // Run ForceAtlas2 layout
    const settings = {
      iterations: 100,
      settings: {
        gravity: 1,
        scalingRatio: 10,
        strongGravityMode: true,
        barnesHutOptimize: true,
        barnesHutTheta: 0.5,
        linLogMode: false,
        adjustSizes: true,
        edgeWeightInfluence: 1,
        slowDown: 1
      }
    };

    forceAtlas2.assign(graph, settings);

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

    sigma = new Sigma(graph, container, {
      renderLabels: true,
      labelRenderedSizeThreshold: labelThreshold,
      labelFont: "Inter, system-ui, sans-serif",
      labelSize: labelSize,
      labelWeight: "500",
      labelColor: { color: "#e5e7eb" },
      defaultNodeColor: "#6b7280",
      defaultEdgeColor: "#374151",
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
          color: "#2d3748",
          zIndex: 0
        };
      },
      // Edge reducer: dim edges not connected to highlighted nodes
      edgeReducer: (edge, data) => {
        if (highlightedNodes.size === 0) {
          return data;
        }
        const source = graph.source(edge);
        const target = graph.target(edge);
        if (highlightedNodes.has(source) && highlightedNodes.has(target)) {
          return { ...data, zIndex: 1 };
        }
        return {
          ...data,
          color: "#1a202c",
          zIndex: 0
        };
      }
    });

    // Handle node hover - highlight connected subgraph
    sigma.on("enterNode", ({ node }) => {
      hoveredNode = node;
      const attrs = graph.getNodeAttributes(node);
      nodeDetails = {
        id: node,
        label: attrs.label,
        type: attrs.nodeType,
        data: attrs.data
      };
      document.body.style.cursor = "pointer";

      // Build set of highlighted nodes: the hovered node + all descendants
      highlightedNodes = new Set([node]);
      collectDescendants(node, highlightedNodes);
      sigma?.refresh();
    });

    sigma.on("leaveNode", () => {
      document.body.style.cursor = "default";

      // If a node is selected, keep its highlighting; otherwise clear
      if (selectedNode) {
        highlightedNodes = new Set([selectedNode]);
        collectDescendants(selectedNode, highlightedNodes);
      } else {
        hoveredNode = null;
        nodeDetails = null;
        highlightedNodes = new Set();
      }
      sigma?.refresh();
    });

    // Handle node click - persist highlighting
    sigma.on("clickNode", ({ node }) => {
      if (selectedNode === node) {
        // Deselect
        selectedNode = null;
        nodeDetails = null;
        highlightedNodes = new Set();
      } else {
        // Select and highlight
        selectedNode = node;
        const attrs = graph.getNodeAttributes(node);
        nodeDetails = {
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
      highlightedNodes = new Set();
      if (!hoveredNode) {
        nodeDetails = null;
      }
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

  function handleResetView() {
    if (sigma) {
      const camera = sigma.getCamera();
      camera.animatedReset({ duration: 300 });
    }
  }

  function handleRelayout() {
    runLayout();
    if (sigma) {
      sigma.refresh();
    }
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

  // Track active pulsation animations: nodeId => {timeout, baseSize, originalColor}
  // Store original values to prevent compounding growth from rapid events
  let activePulsations = new Map<string, {timeout: number, baseSize: number, originalColor: string}>();

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
        // Refresh sigma to show the restored state
        if (sigma) {
          sigma.refresh();
        }
      }
    }, 250);

    activePulsations.set(nodeId, {timeout, baseSize, originalColor});
  }

  // Handle graph activity events - pulsate sensor nodes
  function handleGraphActivity(event: CustomEvent) {
    const { sensor_id, attribute_ids } = event.detail;
    const sensorNodeId = `sensor:${sensor_id}`;

    // Pulsate the sensor node
    if (graph && graph.hasNode(sensorNodeId)) {
      pulsateNode(sensorNodeId);
    }

    // Also pulsate any updated attribute nodes
    if (attribute_ids && Array.isArray(attribute_ids)) {
      for (const attrId of attribute_ids) {
        const attrNodeId = `attr:${sensor_id}:${attrId}`;
        if (graph && graph.hasNode(attrNodeId)) {
          pulsateNode(attrNodeId);
        }
      }
    }

    // Request a refresh from sigma to show the changes
    if (sigma) {
      sigma.refresh();
    }
  }

  // Handle composite measurement events for real-time updates
  function handleCompositeMeasurement(event: CustomEvent) {
    const { sensor_id, attribute_id, payload } = event.detail;
    const attrNodeId = `attr:${sensor_id}:${attribute_id}`;

    if (graph && graph.hasNode(attrNodeId)) {
      const attrs = graph.getNodeAttributes(attrNodeId);
      if (attrs.data) {
        attrs.data.lastvalue = { payload, timestamp: Date.now() };
      }

      // Pulsate the attribute node
      pulsateNode(attrNodeId);

      // Also pulsate the parent sensor node
      const sensorNodeId = `sensor:${sensor_id}`;
      if (graph.hasNode(sensorNodeId)) {
        pulsateNode(sensorNodeId);
      }
    }
  }

  // Rebuild graph when data changes
  $effect(() => {
    if (rooms || users || sensors) {
      buildGraph();
      if (container) {
        initSigma();
      }
    }
  });

  onMount(() => {
    buildGraph();
    initSigma();
    window.addEventListener("composite-measurement-event", handleCompositeMeasurement as EventListener);
    window.addEventListener("graph-activity-event", handleGraphActivity as EventListener);
  });

  onDestroy(() => {
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

<div class="lobby-graph">
  <!-- Graph Container -->
  <div bind:this={container} class="graph-container"></div>

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
    <button onclick={handleResetView} title="Reset View" class="control-btn">
      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 8V4m0 0h4M4 4l5 5m11-1V4m0 0h-4m4 0l-5 5M4 16v4m0 0h4m-4 0l5-5m11 5l-5-5m5 5v-4m0 4h-4" />
      </svg>
    </button>
    <button onclick={handleRelayout} title="Re-layout" class="control-btn" disabled={isLayoutRunning}>
      <svg class="w-5 h-5" class:animate-spin={isLayoutRunning} fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
      </svg>
    </button>
  </div>

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

  <!-- Node Details Panel -->
  {#if nodeDetails}
    <div class="details-panel">
      <div class="details-header">
        <span class="details-icon">{getNodeTypeIcon(nodeDetails.type)}</span>
        <span class="details-type">{nodeDetails.type}</span>
        {#if selectedNode}
          <button onclick={() => { selectedNode = null; nodeDetails = null; }} class="close-btn">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        {/if}
      </div>
      <h3 class="details-title">{nodeDetails.label}</h3>

      {#if nodeDetails.type === "user"}
        <div class="details-content">
          <p><strong>Connector ID:</strong> {nodeDetails.data.connector_id}</p>
          <p><strong>Sensors:</strong> {nodeDetails.data.sensor_count}</p>
          <p><strong>Total Attributes:</strong> {nodeDetails.data.total_attributes}</p>
          {#if nodeDetails.data.attributes_summary?.length > 0}
            <div class="attr-summary">
              <strong>Attribute Types:</strong>
              <ul>
                {#each nodeDetails.data.attributes_summary as attr}
                  <li>{attr.type}: {attr.count}</li>
                {/each}
              </ul>
            </div>
          {/if}
        </div>
      {:else if nodeDetails.type === "sensor"}
        <div class="details-content">
          <p><strong>Sensor ID:</strong> {nodeDetails.data.sensor_id}</p>
          <p><strong>Connector:</strong> {nodeDetails.data.connector_name}</p>
          <p><strong>Attributes:</strong> {Object.keys(nodeDetails.data.attributes || {}).length}</p>
        </div>
      {:else if nodeDetails.type === "attribute"}
        <div class="details-content">
          <p><strong>Attribute ID:</strong> {nodeDetails.data.attribute_id}</p>
          <p><strong>Type:</strong> {nodeDetails.data.attribute_type}</p>
          <p><strong>Sensor:</strong> {nodeDetails.data.sensor_id}</p>
          <div class="attr-value">
            <strong>Value:</strong>
            <pre>{formatAttributeValue(nodeDetails.data)}</pre>
          </div>
        </div>
      {:else if nodeDetails.type === "room"}
        <div class="details-content">
          <p><strong>Room ID:</strong> {nodeDetails.data.id}</p>
          <p><strong>Sensors:</strong> {nodeDetails.data.sensor_count}</p>
        </div>
      {/if}
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

  .graph-container {
    position: absolute;
    inset: 0;
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

  .details-panel {
    position: absolute;
    top: 1rem;
    left: 1rem;
    width: 280px;
    max-height: calc(100vh - 2rem);
    overflow-y: auto;
    background: rgba(17, 24, 39, 0.95);
    border: 1px solid rgba(75, 85, 99, 0.5);
    border-radius: 0.75rem;
    padding: 1rem;
    z-index: 20;
    box-shadow: 0 10px 25px rgba(0, 0, 0, 0.5);
  }

  .details-header {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    margin-bottom: 0.5rem;
  }

  .details-icon {
    font-size: 1.25rem;
  }

  .details-type {
    font-size: 0.7rem;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: #9ca3af;
    flex: 1;
  }

  .close-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 1.5rem;
    height: 1.5rem;
    background: rgba(55, 65, 81, 0.5);
    border: none;
    border-radius: 0.25rem;
    color: #9ca3af;
    cursor: pointer;
  }

  .close-btn:hover {
    background: rgba(75, 85, 99, 0.5);
    color: #d1d5db;
  }

  .details-title {
    font-size: 1rem;
    font-weight: 600;
    color: #f3f4f6;
    margin: 0 0 0.75rem 0;
  }

  .details-content {
    font-size: 0.8rem;
    color: #d1d5db;
  }

  .details-content p {
    margin: 0.375rem 0;
  }

  .details-content strong {
    color: #9ca3af;
  }

  .attr-summary {
    margin-top: 0.5rem;
  }

  .attr-summary ul {
    margin: 0.25rem 0 0 1rem;
    padding: 0;
    list-style: disc;
  }

  .attr-summary li {
    margin: 0.125rem 0;
  }

  .attr-value {
    margin-top: 0.5rem;
  }

  .attr-value pre {
    margin: 0.25rem 0 0 0;
    padding: 0.5rem;
    background: rgba(0, 0, 0, 0.3);
    border-radius: 0.375rem;
    font-size: 0.7rem;
    overflow-x: auto;
    max-height: 150px;
    color: #a5f3fc;
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

  @keyframes spin {
    from { transform: rotate(0deg); }
    to { transform: rotate(360deg); }
  }

  .animate-spin {
    animation: spin 1s linear infinite;
  }
</style>
