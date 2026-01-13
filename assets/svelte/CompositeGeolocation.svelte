<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import * as maplibregl from "maplibre-gl";
  import "maplibre-gl/dist/maplibre-gl.css";
  import Graph from "graphology";
  import Sigma from "sigma";
  import forceAtlas2 from "graphology-layout-forceatlas2";

  let {
    positions = [],
    showTrails = true,
    maxTrailLength = 100,
  }: {
    positions: Array<{ sensor_id: string; lat: number; lng: number; mode?: string; sensor_name?: string }>;
    showTrails?: boolean;
    maxTrailLength?: number;
  } = $props();

  type ViewMode = "map" | "graph" | "split";
  let viewMode: ViewMode = $state("split");

  // Map state
  let mapContainer: HTMLDivElement;
  let map: maplibregl.Map | null = null;
  let markers: Map<string, maplibregl.Marker> = new Map();
  let trails: Map<string, Array<[number, number]>> = new Map();

  // Graph state
  let graphContainer: HTMLDivElement;
  let sigma: Sigma | null = null;
  let graph: Graph | null = null;

  // Shared state
  let sensorColorIndex: Map<string, number> = new Map();
  let nextColorIndex = 0;

  const MARKER_COLORS = [
    '#ef4444', '#f97316', '#eab308', '#22c55e', '#14b8a6',
    '#0ea5e9', '#6366f1', '#a855f7', '#ec4899', '#f43f5e',
    '#84cc16', '#06b6d4', '#8b5cf6', '#f472b6', '#fb923c'
  ];

  const MODE_ICONS: Record<string, string> = {
    walk: '🚶', cycle: '🚴', car: '🚗', train: '🚆',
    bird: '🦅', drone: '🛸', boat: '⛵'
  };

  function getMarkerColor(sensorId: string): string {
    if (!sensorColorIndex.has(sensorId)) {
      sensorColorIndex.set(sensorId, nextColorIndex);
      nextColorIndex = (nextColorIndex + 1) % MARKER_COLORS.length;
    }
    return MARKER_COLORS[sensorColorIndex.get(sensorId)!];
  }

  function getModeIcon(mode?: string): string {
    return mode ? (MODE_ICONS[mode] || '📍') : '📍';
  }

  // Haversine formula for distance in meters
  function haversineDistance(lat1: number, lng1: number, lat2: number, lng2: number): number {
    const R = 6371000;
    const phi1 = (lat1 * Math.PI) / 180;
    const phi2 = (lat2 * Math.PI) / 180;
    const deltaPhi = ((lat2 - lat1) * Math.PI) / 180;
    const deltaLambda = ((lng2 - lng1) * Math.PI) / 180;
    const a = Math.sin(deltaPhi / 2) ** 2 + Math.cos(phi1) * Math.cos(phi2) * Math.sin(deltaLambda / 2) ** 2;
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
  }

  function formatDistance(meters: number): string {
    if (meters < 1000) return `${Math.round(meters)}m`;
    return `${(meters / 1000).toFixed(2)}km`;
  }

  // ===== MAP FUNCTIONS =====
  function createMarkerElement(color: string, sensorId: string, mode?: string): HTMLDivElement {
    const el = document.createElement('div');
    el.className = 'composite-map-marker';
    const icon = getModeIcon(mode);
    const shortId = sensorId.length > 12 ? sensorId.slice(0, 10) + '...' : sensorId;
    el.innerHTML = `
      <div class="marker-icon" style="background-color: ${color}">
        <span class="mode-icon">${icon}</span>
      </div>
      <span class="marker-label">${shortId}</span>
    `;
    return el;
  }

  function updateTrail(sensorId: string, lng: number, lat: number) {
    if (!showTrails || !map) return;
    let trail = trails.get(sensorId) || [];
    trail.push([lng, lat]);
    if (trail.length > maxTrailLength) trail = trail.slice(-maxTrailLength);
    trails.set(sensorId, trail);

    const sourceId = `trail-${sensorId}`;
    const layerId = `trail-line-${sensorId}`;

    if (trail.length >= 2) {
      const geojson: GeoJSON.Feature<GeoJSON.LineString> = {
        type: 'Feature', properties: {},
        geometry: { type: 'LineString', coordinates: trail }
      };
      const source = map.getSource(sourceId) as maplibregl.GeoJSONSource;
      if (source) {
        source.setData(geojson);
      } else {
        map.addSource(sourceId, { type: 'geojson', data: geojson });
        map.addLayer({
          id: layerId, type: 'line', source: sourceId,
          layout: { 'line-join': 'round', 'line-cap': 'round' },
          paint: { 'line-color': getMarkerColor(sensorId), 'line-width': 3, 'line-opacity': 0.7 }
        });
      }
    }
  }

  function updateMapMarkers() {
    if (!map) return;
    const existingIds = new Set(markers.keys());
    const newIds = new Set(positions.map(p => p.sensor_id));

    existingIds.forEach(id => {
      if (!newIds.has(id)) {
        markers.get(id)?.remove();
        markers.delete(id);
        const sourceId = `trail-${id}`;
        const layerId = `trail-line-${id}`;
        if (map!.getLayer(layerId)) map!.removeLayer(layerId);
        if (map!.getSource(sourceId)) map!.removeSource(sourceId);
        trails.delete(id);
      }
    });

    positions.forEach((position) => {
      if (position.lat === 0 && position.lng === 0) return;
      const color = getMarkerColor(position.sensor_id);
      const existingMarker = markers.get(position.sensor_id);

      if (existingMarker) {
        existingMarker.setLngLat([position.lng, position.lat]);
      } else {
        const el = createMarkerElement(color, position.sensor_id, position.mode);
        const marker = new maplibregl.Marker({ element: el, anchor: 'bottom' })
          .setLngLat([position.lng, position.lat])
          .addTo(map!);
        markers.set(position.sensor_id, marker);
      }
      updateTrail(position.sensor_id, position.lng, position.lat);
    });
  }

  function fitMapBounds() {
    if (!map || positions.length === 0) return;
    const validPositions = positions.filter(p => p.lat !== 0 || p.lng !== 0);
    if (validPositions.length === 0) return;

    if (validPositions.length === 1) {
      map.flyTo({ center: [validPositions[0].lng, validPositions[0].lat], zoom: 14, duration: 1000 });
    } else {
      const bounds = new maplibregl.LngLatBounds();
      validPositions.forEach(p => bounds.extend([p.lng, p.lat]));
      trails.forEach((trail) => trail.forEach(coord => bounds.extend(coord)));
      map.fitBounds(bounds, { padding: 60, maxZoom: 15, duration: 1000 });
    }
  }

  function initMap() {
    if (!mapContainer || map) return;
    const defaultCenter = positions.length > 0 && (positions[0].lat !== 0 || positions[0].lng !== 0)
      ? [positions[0].lng, positions[0].lat] : [13.405, 52.52];

    map = new maplibregl.Map({
      container: mapContainer,
      style: "https://demotiles.maplibre.org/style.json",
      center: defaultCenter as [number, number],
      zoom: 10, attributionControl: false, maxZoom: 18, minZoom: 2
    });

    map.addControl(new maplibregl.NavigationControl(), 'top-right');
    map.addControl(new maplibregl.ScaleControl({ maxWidth: 100 }), 'bottom-left');
    map.on('load', () => { updateMapMarkers(); fitMapBounds(); });
  }

  function clearTrails() {
    if (!map) return;
    trails.forEach((_, sensorId) => {
      const sourceId = `trail-${sensorId}`;
      const layerId = `trail-line-${sensorId}`;
      if (map!.getLayer(layerId)) map!.removeLayer(layerId);
      if (map!.getSource(sourceId)) map!.removeSource(sourceId);
    });
    trails.clear();
  }

  // ===== GRAPH FUNCTIONS =====
  function buildGraph() {
    if (!graphContainer) return;
    if (sigma) { sigma.kill(); sigma = null; }

    const validPositions = mergedPositions.filter(p => p.lat !== 0 || p.lng !== 0);
    if (validPositions.length === 0) return;

    graph = new Graph();

    const lats = validPositions.map(p => p.lat);
    const lngs = validPositions.map(p => p.lng);
    const minLat = Math.min(...lats), maxLat = Math.max(...lats);
    const minLng = Math.min(...lngs), maxLng = Math.max(...lngs);
    const latRange = maxLat - minLat || 1;
    const lngRange = maxLng - minLng || 1;

    validPositions.forEach((pos) => {
      const x = ((pos.lng - minLng) / lngRange) * 10;
      const y = ((pos.lat - minLat) / latRange) * 10;
      graph!.addNode(pos.sensor_id, {
        label: pos.sensor_name || pos.sensor_id.slice(0, 10),
        x, y, size: 15, color: getMarkerColor(pos.sensor_id),
      });
    });

    for (let i = 0; i < validPositions.length; i++) {
      for (let j = i + 1; j < validPositions.length; j++) {
        const p1 = validPositions[i], p2 = validPositions[j];
        const distance = haversineDistance(p1.lat, p1.lng, p2.lat, p2.lng);
        let edgeColor = '#4b5563';
        if (distance < 100) edgeColor = '#22c55e';
        else if (distance < 1000) edgeColor = '#eab308';
        else if (distance < 10000) edgeColor = '#f97316';
        else edgeColor = '#ef4444';

        const weight = Math.max(0.1, 1 - Math.min(distance, 100000) / 100000);
        graph!.addEdge(p1.sensor_id, p2.sensor_id, {
          label: formatDistance(distance),
          size: Math.max(1, weight * 4),
          color: edgeColor,
        });
      }
    }

    if (validPositions.length > 2) {
      forceAtlas2.assign(graph, {
        iterations: 50,
        settings: { gravity: 1, scalingRatio: 10, strongGravityMode: true, barnesHutOptimize: true }
      });
    }

    sigma = new Sigma(graph, graphContainer, {
      renderLabels: true, renderEdgeLabels: true,
      labelFont: "Inter, system-ui, sans-serif", labelSize: 12, labelWeight: "500",
      labelColor: { color: "#e5e7eb" },
      edgeLabelFont: "Inter, system-ui, sans-serif", edgeLabelSize: 10,
      edgeLabelColor: { color: "#9ca3af" },
      defaultNodeColor: "#6366f1", defaultEdgeColor: "#4b5563",
      minCameraRatio: 0.1, maxCameraRatio: 10,
    });
  }

  function resetGraphCamera() {
    if (sigma) sigma.getCamera().animatedReset({ duration: 500 });
  }

  // ===== DISTANCE MATRIX =====
  let distanceMatrix = $derived.by(() => {
    const validPositions = mergedPositions.filter(p => p.lat !== 0 || p.lng !== 0);
    const matrix: { from: string; fromId: string; to: string; toId: string; distance: number; formatted: string }[] = [];

    for (let i = 0; i < validPositions.length; i++) {
      for (let j = i + 1; j < validPositions.length; j++) {
        const p1 = validPositions[i], p2 = validPositions[j];
        const distance = haversineDistance(p1.lat, p1.lng, p2.lat, p2.lng);
        matrix.push({
          from: p1.sensor_name || p1.sensor_id.slice(0, 12),
          fromId: p1.sensor_id,
          to: p2.sensor_name || p2.sensor_id.slice(0, 12),
          toId: p2.sensor_id,
          distance,
          formatted: formatDistance(distance),
        });
      }
    }
    return matrix.sort((a, b) => a.distance - b.distance);
  });

  // ===== LIFECYCLE =====
  function handleResize() {
    if (map) map.resize();
    if (sigma) sigma.refresh();
  }

  // Local positions state for real-time updates
  let localPositions: Map<string, { lat: number; lng: number; sensor_name?: string; mode?: string }> = $state(new Map());
  let graphNeedsRebuild = $state(false);
  let lastGraphRebuild = 0;

  // Merge props positions with local real-time updates
  let mergedPositions = $derived.by(() => {
    const merged = new Map<string, { sensor_id: string; lat: number; lng: number; sensor_name?: string; mode?: string }>();

    // Start with prop positions
    for (const p of positions) {
      merged.set(p.sensor_id, { ...p });
    }

    // Override with local real-time positions
    for (const [sensorId, pos] of localPositions) {
      if (merged.has(sensorId)) {
        const existing = merged.get(sensorId)!;
        merged.set(sensorId, { ...existing, lat: pos.lat, lng: pos.lng });
      } else {
        merged.set(sensorId, { sensor_id: sensorId, ...pos });
      }
    }

    return Array.from(merged.values());
  });

  // Throttled graph rebuild function
  function scheduleGraphRebuild() {
    const now = Date.now();
    if (now - lastGraphRebuild > 2000) { // Rebuild at most every 2 seconds
      lastGraphRebuild = now;
      buildGraph();
    } else if (!graphNeedsRebuild) {
      graphNeedsRebuild = true;
      setTimeout(() => {
        graphNeedsRebuild = false;
        lastGraphRebuild = Date.now();
        buildGraph();
      }, 2000 - (now - lastGraphRebuild));
    }
  }

  onMount(async () => {
    await new Promise(resolve => setTimeout(resolve, 100));
    if (viewMode === "map" || viewMode === "split") initMap();
    if (viewMode === "graph" || viewMode === "split") buildGraph();

    const handleCompositeMeasurement = (e: CustomEvent) => {
      const { sensor_id, attribute_id, payload } = e.detail;
      if (attribute_id === "geolocation") {
        const lat = payload?.latitude || payload?.lat || 0;
        const lng = payload?.longitude || payload?.lng || 0;
        if (lat === 0 && lng === 0) return;

        // Update local positions for graph/distance matrix
        localPositions.set(sensor_id, {
          lat, lng,
          sensor_name: payload?.sensor_name,
          mode: payload?.mode
        });
        localPositions = new Map(localPositions); // Trigger reactivity

        // Update map marker immediately
        if (map) {
          const color = getMarkerColor(sensor_id);
          const existingMarker = markers.get(sensor_id);
          if (existingMarker) {
            existingMarker.setLngLat([lng, lat]);
          } else {
            const el = createMarkerElement(color, sensor_id, payload?.mode);
            const marker = new maplibregl.Marker({ element: el, anchor: 'bottom' })
              .setLngLat([lng, lat]).addTo(map!);
            markers.set(sensor_id, marker);
          }
          updateTrail(sensor_id, lng, lat);
        }

        // Schedule graph rebuild (throttled)
        if (viewMode === "graph" || viewMode === "split") {
          scheduleGraphRebuild();
        }
      }
    };

    window.addEventListener("composite-measurement-event", handleCompositeMeasurement as EventListener);
    window.addEventListener('resize', handleResize);

    return () => {
      window.removeEventListener("composite-measurement-event", handleCompositeMeasurement as EventListener);
      window.removeEventListener('resize', handleResize);
    };
  });

  $effect(() => {
    if (viewMode === "map" || viewMode === "split") {
      setTimeout(() => { initMap(); updateMapMarkers(); }, 50);
    }
    if (viewMode === "graph" || viewMode === "split") {
      setTimeout(() => buildGraph(), 50);
    }
  });

  $effect(() => {
    if (positions && map) {
      updateMapMarkers();
    }
    if (positions && graphContainer) {
      buildGraph();
    }
  });

  onDestroy(() => {
    window.removeEventListener("resize", handleResize);
    if (map) map.remove();
    if (sigma) sigma.kill();
  });
</script>

<div class="geolocation-container">
  <div class="toolbar">
    <div class="view-tabs">
      <button class="tab" class:active={viewMode === "split"} onclick={() => viewMode = "split"}>
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 5a1 1 0 011-1h4a1 1 0 011 1v4a1 1 0 01-1 1H5a1 1 0 01-1-1V5zM14 5a1 1 0 011-1h4a1 1 0 011 1v4a1 1 0 01-1 1h-4a1 1 0 01-1-1V5zM4 15a1 1 0 011-1h4a1 1 0 011 1v4a1 1 0 01-1 1H5a1 1 0 01-1-1v-4zM14 15a1 1 0 011-1h4a1 1 0 011 1v4a1 1 0 01-1 1h-4a1 1 0 01-1-1v-4z" />
        </svg>
        Split
      </button>
      <button class="tab" class:active={viewMode === "map"} onclick={() => viewMode = "map"}>
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 20l-5.447-2.724A1 1 0 013 16.382V5.618a1 1 0 011.447-.894L9 7m0 13l6-3m-6 3V7m6 10l4.553 2.276A1 1 0 0021 18.382V7.618a1 1 0 00-.553-.894L15 4m0 13V4m0 0L9 7" />
        </svg>
        Map
      </button>
      <button class="tab" class:active={viewMode === "graph"} onclick={() => viewMode = "graph"}>
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1" />
        </svg>
        Graph
      </button>
    </div>
    <div class="sensor-count">
      {positions.filter(p => p.lat !== 0 || p.lng !== 0).length} sensors
    </div>
  </div>

  <div class="views-container" class:split-view={viewMode === "split"}>
    {#if viewMode === "map" || viewMode === "split"}
      <div class="map-panel" class:full={viewMode === "map"}>
        <div bind:this={mapContainer} class="map-element"></div>
        <div class="map-controls">
          <button class="control-btn" onclick={fitMapBounds} title="Fit all markers">🎯</button>
          {#if showTrails}
            <button class="control-btn" onclick={clearTrails} title="Clear trails">🧹</button>
          {/if}
        </div>
      </div>
    {/if}

    {#if viewMode === "graph" || viewMode === "split"}
      <div class="graph-panel" class:full={viewMode === "graph"}>
        <div bind:this={graphContainer} class="graph-element"></div>
        <div class="graph-controls">
          <button class="control-btn" onclick={resetGraphCamera} title="Reset view">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 8V4m0 0h4M4 4l5 5m11-1V4m0 0h-4m4 0l-5 5M4 16v4m0 0h4m-4 0l5-5m11 5l-5-5m5 5v-4m0 4h-4" />
            </svg>
          </button>
        </div>
        <div class="graph-legend">
          <span class="legend-item"><span class="dot green"></span>&lt;100m</span>
          <span class="legend-item"><span class="dot yellow"></span>&lt;1km</span>
          <span class="legend-item"><span class="dot orange"></span>&lt;10km</span>
          <span class="legend-item"><span class="dot red"></span>&gt;10km</span>
        </div>
      </div>
    {/if}
  </div>

  {#if distanceMatrix.length > 0}
    <div class="distance-table">
      <div class="table-header">
        <h3>Distance Matrix</h3>
        <span class="count">{distanceMatrix.length} connections</span>
      </div>
      <div class="table-scroll">
        <table>
          <thead>
            <tr><th>From</th><th>To</th><th>Distance</th></tr>
          </thead>
          <tbody>
            {#each distanceMatrix as row}
              <tr>
                <td><span class="sensor-badge" style="background-color: {getMarkerColor(row.fromId)}">{row.from}</span></td>
                <td><span class="sensor-badge" style="background-color: {getMarkerColor(row.toId)}">{row.to}</span></td>
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
  .geolocation-container {
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
    width: 100%;
    height: 100%;
    min-height: 500px;
  }

  .toolbar {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 0.5rem 0.75rem;
    background: rgba(31, 41, 55, 0.8);
    border-radius: 0.5rem;
    border: 1px solid rgba(75, 85, 99, 0.5);
  }

  .view-tabs {
    display: flex;
    gap: 0.25rem;
  }

  .tab {
    display: flex;
    align-items: center;
    gap: 0.375rem;
    padding: 0.375rem 0.75rem;
    border-radius: 0.375rem;
    background: transparent;
    border: 1px solid transparent;
    color: #9ca3af;
    font-size: 0.8125rem;
    cursor: pointer;
    transition: all 0.2s;
  }

  .tab:hover { background: rgba(55, 65, 81, 0.5); color: #d1d5db; }
  .tab.active { background: rgba(99, 102, 241, 0.2); border-color: rgba(99, 102, 241, 0.5); color: #a5b4fc; }

  .sensor-count {
    font-size: 0.75rem;
    color: #9ca3af;
    padding: 0.25rem 0.5rem;
    background: rgba(55, 65, 81, 0.5);
    border-radius: 9999px;
  }

  .views-container {
    display: flex;
    flex: 1;
    gap: 0.75rem;
    min-height: 350px;
  }

  .views-container.split-view .map-panel,
  .views-container.split-view .graph-panel {
    flex: 1;
  }

  .map-panel, .graph-panel {
    position: relative;
    background: rgba(31, 41, 55, 0.8);
    border-radius: 0.75rem;
    border: 1px solid rgba(75, 85, 99, 0.5);
    overflow: hidden;
  }

  .map-panel.full, .graph-panel.full { flex: 1; }

  .map-element, .graph-element {
    width: 100%;
    height: 100%;
    min-height: 300px;
  }

  .map-controls, .graph-controls {
    position: absolute;
    top: 0.75rem;
    left: 0.75rem;
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
    z-index: 10;
  }

  .control-btn {
    width: 2rem;
    height: 2rem;
    border-radius: 0.375rem;
    background: rgba(31, 41, 55, 0.9);
    border: 1px solid rgba(75, 85, 99, 0.5);
    color: white;
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 0.875rem;
    transition: all 0.2s;
  }

  .control-btn:hover {
    background: rgba(55, 65, 81, 0.9);
    border-color: rgba(107, 114, 128, 0.7);
  }

  .graph-legend {
    position: absolute;
    bottom: 0.75rem;
    left: 0.75rem;
    display: flex;
    gap: 0.75rem;
    padding: 0.375rem 0.75rem;
    background: rgba(17, 24, 39, 0.9);
    border-radius: 0.375rem;
    border: 1px solid rgba(75, 85, 99, 0.3);
  }

  .legend-item {
    display: flex;
    align-items: center;
    gap: 0.25rem;
    font-size: 0.6875rem;
    color: #9ca3af;
  }

  .dot { width: 0.5rem; height: 0.5rem; border-radius: 50%; }
  .dot.green { background: #22c55e; }
  .dot.yellow { background: #eab308; }
  .dot.orange { background: #f97316; }
  .dot.red { background: #ef4444; }

  .distance-table {
    background: rgba(31, 41, 55, 0.8);
    border-radius: 0.75rem;
    border: 1px solid rgba(75, 85, 99, 0.5);
    overflow: hidden;
  }

  .table-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 0.625rem 1rem;
    border-bottom: 1px solid rgba(75, 85, 99, 0.3);
  }

  .table-header h3 {
    font-size: 0.8125rem;
    font-weight: 600;
    color: #e5e7eb;
    margin: 0;
  }

  .count { font-size: 0.75rem; color: #9ca3af; }

  .table-scroll { max-height: 180px; overflow-y: auto; }

  table { width: 100%; border-collapse: collapse; font-size: 0.8125rem; }

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
    font-size: 0.6875rem;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    border-bottom: 1px solid rgba(75, 85, 99, 0.3);
  }

  td {
    padding: 0.375rem 1rem;
    border-bottom: 1px solid rgba(75, 85, 99, 0.2);
    color: #d1d5db;
  }

  tr:hover { background: rgba(55, 65, 81, 0.3); }

  .sensor-badge {
    display: inline-block;
    padding: 0.125rem 0.5rem;
    border-radius: 9999px;
    font-size: 0.6875rem;
    color: white;
    font-weight: 500;
  }

  .distance-cell { text-align: right; font-family: ui-monospace, monospace; }

  .distance-value {
    display: inline-block;
    padding: 0.125rem 0.375rem;
    border-radius: 0.25rem;
    font-size: 0.75rem;
    font-weight: 500;
  }

  .distance-value.close { background: rgba(34, 197, 94, 0.2); color: #22c55e; }
  .distance-value.near { background: rgba(234, 179, 8, 0.2); color: #eab308; }
  .distance-value.moderate { background: rgba(249, 115, 22, 0.2); color: #f97316; }
  .distance-value.far { background: rgba(239, 68, 68, 0.2); color: #ef4444; }

  :global(.composite-map-marker) {
    cursor: pointer;
    display: flex;
    flex-direction: column;
    align-items: center;
    transition: transform 0.2s;
  }

  :global(.composite-map-marker:hover) { transform: scale(1.1); }

  :global(.composite-map-marker .marker-icon) {
    width: 2rem;
    height: 2rem;
    border-radius: 50%;
    display: flex;
    align-items: center;
    justify-content: center;
    box-shadow: 0 2px 8px rgba(0, 0, 0, 0.4);
    border: 2px solid white;
  }

  :global(.composite-map-marker .mode-icon) { font-size: 1rem; }

  :global(.composite-map-marker .marker-label) {
    font-size: 0.625rem;
    color: white;
    background: rgba(0, 0, 0, 0.8);
    padding: 0.125rem 0.375rem;
    border-radius: 0.25rem;
    margin-top: 0.25rem;
    white-space: nowrap;
    max-width: 100px;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  :global(.maplibregl-ctrl-scale) {
    background: rgba(17, 24, 39, 0.8) !important;
    color: #d1d5db !important;
    border-color: rgba(75, 85, 99, 0.5) !important;
    font-size: 0.625rem !important;
  }
</style>
