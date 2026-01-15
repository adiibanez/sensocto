<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import Graph from "graphology";
  import Sigma from "sigma";
  import forceAtlas2 from "graphology-layout-forceatlas2";

  let {
    positions = [],
  }: {
    positions: Array<{ sensor_id: string; lat: number; lng: number; sensor_name?: string }>;
  } = $props();

  let graphContainer: HTMLDivElement;
  let sigma: Sigma | null = null;
  let graph: Graph | null = null;

  // Track node positions to preserve layout stability
  let nodePositions: Map<string, { x: number; y: number }> = new Map();
  let isInitialBuild = true;

  // Debounce/throttle updates to prevent nervous graph
  let updateTimeout: ReturnType<typeof setTimeout> | null = null;
  let lastUpdateTime = 0;
  const UPDATE_THROTTLE_MS = 500; // Minimum time between updates
  const UPDATE_DEBOUNCE_MS = 200; // Wait before processing rapid updates

  const NODE_COLORS = [
    '#ef4444', '#f97316', '#eab308', '#22c55e', '#14b8a6',
    '#0ea5e9', '#6366f1', '#a855f7', '#ec4899', '#f43f5e',
    '#84cc16', '#06b6d4', '#8b5cf6', '#f472b6', '#fb923c'
  ];

  let sensorColorMap: Map<string, string> = new Map();
  let nextColorIndex = 0;

  function getNodeColor(sensorId: string): string {
    if (!sensorColorMap.has(sensorId)) {
      sensorColorMap.set(sensorId, NODE_COLORS[nextColorIndex % NODE_COLORS.length]);
      nextColorIndex++;
    }
    return sensorColorMap.get(sensorId)!;
  }

  // Haversine formula for distance in meters
  function haversineDistance(lat1: number, lng1: number, lat2: number, lng2: number): number {
    const R = 6371000; // Earth's radius in meters
    const phi1 = (lat1 * Math.PI) / 180;
    const phi2 = (lat2 * Math.PI) / 180;
    const deltaPhi = ((lat2 - lat1) * Math.PI) / 180;
    const deltaLambda = ((lng2 - lng1) * Math.PI) / 180;

    const a =
      Math.sin(deltaPhi / 2) * Math.sin(deltaPhi / 2) +
      Math.cos(phi1) * Math.cos(phi2) * Math.sin(deltaLambda / 2) * Math.sin(deltaLambda / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

    return R * c;
  }

  function formatDistance(meters: number): string {
    if (meters < 1000) {
      return `${Math.round(meters)}m`;
    } else {
      return `${(meters / 1000).toFixed(2)}km`;
    }
  }

  // Calculate edge weight (inverse of distance for layout, capped)
  function calculateEdgeWeight(distance: number): number {
    // Closer nodes should have stronger connections
    // Cap at 100km to avoid extreme values
    const maxDist = 100000;
    const normalizedDist = Math.min(distance, maxDist);
    return 1 - normalizedDist / maxDist;
  }

  function getEdgeColor(distance: number): string {
    if (distance < 100) return '#22c55e'; // green - very close
    if (distance < 1000) return '#eab308'; // yellow - nearby
    if (distance < 10000) return '#f97316'; // orange - moderate
    return '#ef4444'; // red - far
  }

  function getEdgeKey(id1: string, id2: string): string {
    return [id1, id2].sort().join('--');
  }

  // Save current positions from sigma before rebuilding
  function saveNodePositions() {
    if (!graph || !sigma) return;
    graph.forEachNode((nodeId, attrs) => {
      nodePositions.set(nodeId, { x: attrs.x, y: attrs.y });
    });
  }

  // Initialize the graph and sigma instance (called once)
  function initGraph() {
    if (!graphContainer) return;

    if (sigma) {
      sigma.kill();
      sigma = null;
    }

    graph = new Graph();

    sigma = new Sigma(graph, graphContainer, {
      renderLabels: true,
      renderEdgeLabels: true,
      labelFont: "Inter, system-ui, sans-serif",
      labelSize: 12,
      labelWeight: "500",
      labelColor: { color: "#e5e7eb" },
      edgeLabelFont: "Inter, system-ui, sans-serif",
      edgeLabelSize: 10,
      edgeLabelColor: { color: "#9ca3af" },
      defaultNodeColor: "#6366f1",
      defaultEdgeColor: "#4b5563",
      minCameraRatio: 0.1,
      maxCameraRatio: 10,
    });

    isInitialBuild = true;
  }

  // Update graph data without destroying sigma (preserves layout)
  function updateGraph() {
    if (!graphContainer || !graph || !sigma) {
      initGraph();
      if (!graph || !sigma) return;
    }

    const validPositions = positions.filter(p => p.lat !== 0 || p.lng !== 0);

    // Get current node IDs and new node IDs
    const currentNodeIds = new Set(graph.nodes());
    const newNodeIds = new Set(validPositions.map(p => p.sensor_id));

    // Calculate bounds for initial positioning of new nodes
    const lats = validPositions.map(p => p.lat);
    const lngs = validPositions.map(p => p.lng);
    const minLat = Math.min(...lats);
    const maxLat = Math.max(...lats);
    const minLng = Math.min(...lngs);
    const maxLng = Math.max(...lngs);
    const latRange = maxLat - minLat || 1;
    const lngRange = maxLng - minLng || 1;

    // Remove nodes that no longer exist
    for (const nodeId of currentNodeIds) {
      if (!newNodeIds.has(nodeId)) {
        graph.dropNode(nodeId);
        nodePositions.delete(nodeId);
      }
    }

    // Add or update nodes
    validPositions.forEach((pos) => {
      const existingPos = nodePositions.get(pos.sensor_id);

      if (graph!.hasNode(pos.sensor_id)) {
        // Update existing node label (position preserved by sigma)
        graph!.setNodeAttribute(pos.sensor_id, 'label', pos.sensor_name || pos.sensor_id.slice(0, 10));
      } else {
        // Add new node - use saved position or calculate initial position
        let x: number, y: number;
        if (existingPos) {
          x = existingPos.x;
          y = existingPos.y;
        } else {
          // Position new nodes based on geo coords
          x = ((pos.lng - minLng) / lngRange) * 10;
          y = ((pos.lat - minLat) / latRange) * 10;
        }

        graph!.addNode(pos.sensor_id, {
          label: pos.sensor_name || pos.sensor_id.slice(0, 10),
          x: x,
          y: y,
          size: 15,
          color: getNodeColor(pos.sensor_id),
        });
      }
    });

    // Update edges - track which edges should exist
    const expectedEdges = new Set<string>();

    for (let i = 0; i < validPositions.length; i++) {
      for (let j = i + 1; j < validPositions.length; j++) {
        const p1 = validPositions[i];
        const p2 = validPositions[j];
        const edgeKey = getEdgeKey(p1.sensor_id, p2.sensor_id);
        expectedEdges.add(edgeKey);

        const distance = haversineDistance(p1.lat, p1.lng, p2.lat, p2.lng);
        const weight = calculateEdgeWeight(distance);
        const edgeColor = getEdgeColor(distance);
        const edgeLabel = formatDistance(distance);

        // Check if edge exists
        const existingEdge = graph!.edge(p1.sensor_id, p2.sensor_id);

        if (existingEdge) {
          // Update existing edge attributes
          graph!.setEdgeAttribute(existingEdge, 'label', edgeLabel);
          graph!.setEdgeAttribute(existingEdge, 'color', edgeColor);
          graph!.setEdgeAttribute(existingEdge, 'size', Math.max(1, weight * 4));
          graph!.setEdgeAttribute(existingEdge, 'distance', distance);
        } else {
          // Add new edge
          graph!.addEdge(p1.sensor_id, p2.sensor_id, {
            label: edgeLabel,
            size: Math.max(1, weight * 4),
            color: edgeColor,
            distance: distance,
          });
        }
      }
    }

    // Remove edges that no longer should exist
    graph!.forEachEdge((edge, attrs, source, target) => {
      const edgeKey = getEdgeKey(source, target);
      if (!expectedEdges.has(edgeKey)) {
        graph!.dropEdge(edge);
      }
    });

    // Only apply force layout on initial build or when new nodes are added
    const hasNewNodes = validPositions.some(p => !currentNodeIds.has(p.sensor_id));

    if ((isInitialBuild || hasNewNodes) && validPositions.length > 2) {
      // Apply gentle force layout - fewer iterations to avoid major disruption
      forceAtlas2.assign(graph, {
        iterations: isInitialBuild ? 50 : 10,
        settings: {
          gravity: 1,
          scalingRatio: 10,
          strongGravityMode: true,
          barnesHutOptimize: true,
          slowDown: isInitialBuild ? 1 : 10, // Slow down updates for stability
        },
      });
      isInitialBuild = false;
    }

    // Refresh sigma to show changes
    sigma!.refresh();
  }

  // Throttled and debounced graph update to prevent nervous behavior
  function scheduleUpdate() {
    const now = Date.now();
    const timeSinceLastUpdate = now - lastUpdateTime;

    // Clear any pending update
    if (updateTimeout) {
      clearTimeout(updateTimeout);
      updateTimeout = null;
    }

    // If enough time has passed, update immediately
    if (timeSinceLastUpdate >= UPDATE_THROTTLE_MS) {
      lastUpdateTime = now;
      updateGraph();
    } else {
      // Otherwise, debounce the update
      updateTimeout = setTimeout(() => {
        lastUpdateTime = Date.now();
        updateGraph();
        updateTimeout = null;
      }, UPDATE_DEBOUNCE_MS);
    }
  }

  // Legacy function name for compatibility
  function buildGraph() {
    // On initial build, update immediately; otherwise throttle
    if (isInitialBuild) {
      updateGraph();
    } else {
      scheduleUpdate();
    }
  }

  function handleResize() {
    if (sigma) {
      sigma.refresh();
    }
  }

  function resetCamera() {
    if (sigma) {
      const camera = sigma.getCamera();
      camera.animatedReset({ duration: 500 });
    }
  }

  onMount(() => {
    buildGraph();
    window.addEventListener("resize", handleResize);

    // Listen for position updates
    const handleCompositeMeasurement = (e: CustomEvent) => {
      const { attribute_id } = e.detail;
      if (attribute_id === "geolocation") {
        // Rebuild graph when positions update
        buildGraph();
      }
    };

    window.addEventListener(
      "composite-measurement-event",
      handleCompositeMeasurement as EventListener
    );

    return () => {
      window.removeEventListener(
        "composite-measurement-event",
        handleCompositeMeasurement as EventListener
      );
    };
  });

  // Reactive rebuild when positions change
  $effect(() => {
    if (positions) {
      buildGraph();
    }
  });

  onDestroy(() => {
    window.removeEventListener("resize", handleResize);
    if (updateTimeout) {
      clearTimeout(updateTimeout);
    }
    if (sigma) {
      sigma.kill();
    }
  });

  // Compute distance matrix for the table
  let distanceMatrix = $derived.by(() => {
    const validPositions = positions.filter(p => p.lat !== 0 || p.lng !== 0);
    const matrix: { from: string; to: string; distance: number; formatted: string }[] = [];

    for (let i = 0; i < validPositions.length; i++) {
      for (let j = i + 1; j < validPositions.length; j++) {
        const p1 = validPositions[i];
        const p2 = validPositions[j];
        const distance = haversineDistance(p1.lat, p1.lng, p2.lat, p2.lng);
        matrix.push({
          from: p1.sensor_name || p1.sensor_id.slice(0, 12),
          to: p2.sensor_name || p2.sensor_id.slice(0, 12),
          distance,
          formatted: formatDistance(distance),
        });
      }
    }

    return matrix.sort((a, b) => a.distance - b.distance);
  });
</script>

<div class="geolocation-graph-container">
  <div class="graph-section">
    <div class="section-header">
      <h3>Sensor Distance Graph</h3>
      <div class="controls">
        <button class="control-btn" onclick={resetCamera} title="Reset view">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 8V4m0 0h4M4 4l5 5m11-1V4m0 0h-4m4 0l-5 5M4 16v4m0 0h4m-4 0l5-5m11 5l-5-5m5 5v-4m0 4h-4" />
          </svg>
        </button>
      </div>
    </div>
    <div bind:this={graphContainer} class="graph-element"></div>
    <div class="legend">
      <span class="legend-item"><span class="dot green"></span> &lt;100m</span>
      <span class="legend-item"><span class="dot yellow"></span> &lt;1km</span>
      <span class="legend-item"><span class="dot orange"></span> &lt;10km</span>
      <span class="legend-item"><span class="dot red"></span> &gt;10km</span>
    </div>
  </div>

  {#if distanceMatrix.length > 0}
    <div class="distance-table-section">
      <div class="section-header">
        <h3>Distance Matrix</h3>
        <span class="count">{distanceMatrix.length} connections</span>
      </div>
      <div class="table-wrapper">
        <table>
          <thead>
            <tr>
              <th>From</th>
              <th>To</th>
              <th>Distance</th>
            </tr>
          </thead>
          <tbody>
            {#each distanceMatrix as row}
              <tr>
                <td>
                  <span class="sensor-badge" style="background-color: {getNodeColor(positions.find(p => (p.sensor_name || p.sensor_id.slice(0, 12)) === row.from)?.sensor_id || '')}">{row.from}</span>
                </td>
                <td>
                  <span class="sensor-badge" style="background-color: {getNodeColor(positions.find(p => (p.sensor_name || p.sensor_id.slice(0, 12)) === row.to)?.sensor_id || '')}">{row.to}</span>
                </td>
                <td class="distance-cell">
                  <span class="distance-value" class:close={row.distance < 100} class:near={row.distance >= 100 && row.distance < 1000} class:moderate={row.distance >= 1000 && row.distance < 10000} class:far={row.distance >= 10000}>
                    {row.formatted}
                  </span>
                </td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
    </div>
  {/if}
</div>

<style>
  .geolocation-graph-container {
    display: flex;
    flex-direction: column;
    gap: 1rem;
    width: 100%;
    height: 100%;
  }

  .graph-section {
    background: rgba(31, 41, 55, 0.8);
    border-radius: 0.75rem;
    border: 1px solid rgba(75, 85, 99, 0.5);
    overflow: hidden;
    display: flex;
    flex-direction: column;
  }

  .section-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 0.75rem 1rem;
    border-bottom: 1px solid rgba(75, 85, 99, 0.3);
  }

  .section-header h3 {
    font-size: 0.875rem;
    font-weight: 600;
    color: #e5e7eb;
    margin: 0;
  }

  .count {
    font-size: 0.75rem;
    color: #9ca3af;
  }

  .controls {
    display: flex;
    gap: 0.5rem;
  }

  .control-btn {
    padding: 0.375rem;
    border-radius: 0.375rem;
    background: rgba(55, 65, 81, 0.5);
    border: 1px solid rgba(75, 85, 99, 0.5);
    color: #d1d5db;
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    transition: all 0.2s;
  }

  .control-btn:hover {
    background: rgba(75, 85, 99, 0.5);
    color: #fff;
  }

  .graph-element {
    flex: 1;
    min-height: 300px;
    background: #1f2937;
  }

  .legend {
    display: flex;
    gap: 1rem;
    padding: 0.5rem 1rem;
    border-top: 1px solid rgba(75, 85, 99, 0.3);
    background: rgba(17, 24, 39, 0.5);
  }

  .legend-item {
    display: flex;
    align-items: center;
    gap: 0.375rem;
    font-size: 0.75rem;
    color: #9ca3af;
  }

  .dot {
    width: 0.5rem;
    height: 0.5rem;
    border-radius: 50%;
  }

  .dot.green { background: #22c55e; }
  .dot.yellow { background: #eab308; }
  .dot.orange { background: #f97316; }
  .dot.red { background: #ef4444; }

  .distance-table-section {
    background: rgba(31, 41, 55, 0.8);
    border-radius: 0.75rem;
    border: 1px solid rgba(75, 85, 99, 0.5);
    overflow: hidden;
  }

  .table-wrapper {
    max-height: 200px;
    overflow-y: auto;
  }

  table {
    width: 100%;
    border-collapse: collapse;
    font-size: 0.8125rem;
  }

  thead {
    position: sticky;
    top: 0;
    background: rgba(17, 24, 39, 0.95);
    z-index: 1;
  }

  th {
    text-align: left;
    padding: 0.5rem 1rem;
    color: #9ca3af;
    font-weight: 500;
    font-size: 0.75rem;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    border-bottom: 1px solid rgba(75, 85, 99, 0.3);
  }

  td {
    padding: 0.5rem 1rem;
    border-bottom: 1px solid rgba(75, 85, 99, 0.2);
    color: #d1d5db;
  }

  tr:hover {
    background: rgba(55, 65, 81, 0.3);
  }

  .sensor-badge {
    display: inline-block;
    padding: 0.125rem 0.5rem;
    border-radius: 9999px;
    font-size: 0.75rem;
    color: white;
    font-weight: 500;
  }

  .distance-cell {
    text-align: right;
    font-family: ui-monospace, monospace;
  }

  .distance-value {
    display: inline-block;
    padding: 0.125rem 0.5rem;
    border-radius: 0.25rem;
    font-weight: 500;
  }

  .distance-value.close {
    background: rgba(34, 197, 94, 0.2);
    color: #22c55e;
  }

  .distance-value.near {
    background: rgba(234, 179, 8, 0.2);
    color: #eab308;
  }

  .distance-value.moderate {
    background: rgba(249, 115, 22, 0.2);
    color: #f97316;
  }

  .distance-value.far {
    background: rgba(239, 68, 68, 0.2);
    color: #ef4444;
  }
</style>
