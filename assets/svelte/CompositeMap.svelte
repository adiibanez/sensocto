<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import * as maplibregl from "maplibre-gl";
  import "maplibre-gl/dist/maplibre-gl.css";

  let {
    positions = [],
    showTrails = true,
    maxTrailLength = 100,
    clusterMarkers = true
  }: {
    positions: Array<{ sensor_id: string; lat: number; lng: number; mode?: string; username?: string }>;
    showTrails?: boolean;
    maxTrailLength?: number;
    clusterMarkers?: boolean;
  } = $props();

  // Store username mapping for realtime updates (username comes from initial props)
  let usernameMap: Map<string, string> = new Map();

  // Update username map when positions change
  $effect(() => {
    positions.forEach(p => {
      if (p.username) {
        usernameMap.set(p.sensor_id, p.username);
      }
    });
  });

  // Get display name: prefer username (email prefix), fallback to sensor_id
  function getDisplayName(sensorId: string, username?: string): string {
    const name = username || usernameMap.get(sensorId);
    if (name) {
      // Extract username from email (part before @)
      const emailMatch = name.match(/^([^@]+)@/);
      return emailMatch ? emailMatch[1] : name;
    }
    return sensorId.length > 12 ? sensorId.slice(0, 10) + '...' : sensorId;
  }

  let mapContainer: HTMLDivElement;
  let map: maplibregl.Map | null = null;
  let markers: Map<string, maplibregl.Marker> = new Map();
  let trails: Map<string, Array<[number, number]>> = new Map();
  let sensorColorIndex: Map<string, number> = new Map();
  let nextColorIndex = 0;
  let _cleanupListeners: (() => void) | null = null;

  const MARKER_COLORS = [
    '#ef4444', '#f97316', '#eab308', '#22c55e', '#14b8a6',
    '#0ea5e9', '#6366f1', '#a855f7', '#ec4899', '#f43f5e',
    '#84cc16', '#06b6d4', '#8b5cf6', '#f472b6', '#fb923c'
  ];

  const MODE_ICONS: Record<string, string> = {
    walk: '🚶',
    cycle: '🚴',
    car: '🚗',
    train: '🚆',
    bird: '🦅',
    drone: '🛸',
    boat: '⛵'
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

  function createMarkerElement(color: string, sensorId: string, mode?: string, username?: string): HTMLDivElement {
    const el = document.createElement('div');
    el.className = 'composite-map-marker';
    const icon = getModeIcon(mode);
    const displayName = getDisplayName(sensorId, username);

    el.innerHTML = `
      <div class="marker-icon" style="background-color: ${color}">
        <span class="mode-icon">${icon}</span>
      </div>
      <span class="marker-label">${displayName}</span>
    `;
    return el;
  }

  function updateTrail(sensorId: string, lng: number, lat: number) {
    if (!showTrails || !map) return;

    let trail = trails.get(sensorId) || [];
    trail.push([lng, lat]);

    if (trail.length > maxTrailLength) {
      trail = trail.slice(-maxTrailLength);
    }
    trails.set(sensorId, trail);

    const sourceId = `trail-${sensorId}`;
    const layerId = `trail-line-${sensorId}`;

    if (trail.length >= 2) {
      const geojson: GeoJSON.Feature<GeoJSON.LineString> = {
        type: 'Feature',
        properties: {},
        geometry: {
          type: 'LineString',
          coordinates: trail
        }
      };

      const source = map.getSource(sourceId) as maplibregl.GeoJSONSource;
      if (source) {
        source.setData(geojson);
      } else {
        map.addSource(sourceId, {
          type: 'geojson',
          data: geojson
        });

        const color = getMarkerColor(sensorId);
        map.addLayer({
          id: layerId,
          type: 'line',
          source: sourceId,
          layout: {
            'line-join': 'round',
            'line-cap': 'round'
          },
          paint: {
            'line-color': color,
            'line-width': 3,
            'line-opacity': 0.7
          }
        });
      }
    }
  }

  function updateMarkers() {
    if (!map) return;

    const existingIds = new Set(markers.keys());
    const newIds = new Set(positions.map(p => p.sensor_id));

    existingIds.forEach(id => {
      if (!newIds.has(id)) {
        markers.get(id)?.remove();
        markers.delete(id);

        const sourceId = `trail-${id}`;
        const layerId = `trail-line-${id}`;
        if (map!.getLayer(layerId)) {
          map!.removeLayer(layerId);
        }
        if (map!.getSource(sourceId)) {
          map!.removeSource(sourceId);
        }
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
        const el = createMarkerElement(color, position.sensor_id, position.mode, position.username);

        const marker = new maplibregl.Marker({
          element: el,
          anchor: 'bottom'
        })
          .setLngLat([position.lng, position.lat])
          .addTo(map!);

        markers.set(position.sensor_id, marker);
      }

      updateTrail(position.sensor_id, position.lng, position.lat);
    });

    fitBoundsToPositions();
  }

  function fitBoundsToPositions() {
    if (!map || positions.length === 0) return;

    const validPositions = positions.filter(p => p.lat !== 0 || p.lng !== 0);
    if (validPositions.length === 0) return;

    if (validPositions.length === 1) {
      map.flyTo({
        center: [validPositions[0].lng, validPositions[0].lat],
        zoom: 14,
        duration: 1000
      });
    } else {
      const bounds = new maplibregl.LngLatBounds();
      validPositions.forEach(p => bounds.extend([p.lng, p.lat]));

      trails.forEach((trail) => {
        trail.forEach(coord => bounds.extend(coord));
      });

      map.fitBounds(bounds, {
        padding: 60,
        maxZoom: 15,
        duration: 1000
      });
    }
  }

  function initMap() {
    if (!mapContainer) return;

    const defaultCenter = positions.length > 0 && (positions[0].lat !== 0 || positions[0].lng !== 0)
      ? [positions[0].lng, positions[0].lat]
      : [13.405, 52.52];

    map = new maplibregl.Map({
      container: mapContainer,
      style: "https://demotiles.maplibre.org/style.json",
      center: defaultCenter as [number, number],
      zoom: 10,
      attributionControl: false,
      maxZoom: 18,
      minZoom: 2
    });

    map.addControl(new maplibregl.NavigationControl(), 'top-right');
    map.addControl(new maplibregl.ScaleControl({ maxWidth: 100 }), 'bottom-left');

    map.on('load', () => {
      updateMarkers();
    });
  }

  onMount(async () => {
    await new Promise(resolve => setTimeout(resolve, 100));
    initMap();

    const handleCompositeMeasurement = (e: CustomEvent) => {
      const { sensor_id, attribute_id, payload, username } = e.detail;

      // Store username if provided (for display name lookup)
      if (username) {
        usernameMap.set(sensor_id, username);
      }

      if (attribute_id === "geolocation" && map) {
        const lat = payload?.latitude || payload?.lat || 0;
        const lng = payload?.longitude || payload?.lng || 0;
        const mode = payload?.mode;

        if (lat === 0 && lng === 0) return;

        const color = getMarkerColor(sensor_id);
        const existingMarker = markers.get(sensor_id);

        if (existingMarker) {
          existingMarker.setLngLat([lng, lat]);
        } else {
          // Use username from event or stored in map
          const el = createMarkerElement(color, sensor_id, mode, username || usernameMap.get(sensor_id));

          const marker = new maplibregl.Marker({
            element: el,
            anchor: 'bottom'
          })
            .setLngLat([lng, lat])
            .addTo(map!);

          markers.set(sensor_id, marker);
        }

        updateTrail(sensor_id, lng, lat);
      }
    };

    const handleAccumulatorEvent = (e: CustomEvent) => {
      const eventSensorId = e?.detail?.sensor_id;
      const attributeId = e?.detail?.attribute_id;

      if (attributeId === "geolocation") {
        const data = e?.detail?.data;
        let payload: any = null;

        if (Array.isArray(data) && data.length > 0) {
          const lastMeasurement = data[data.length - 1];
          payload = lastMeasurement?.payload;
        } else if (data?.payload !== undefined) {
          payload = data.payload;
        }

        if (payload && map) {
          const lat = payload.latitude || payload.lat || 0;
          const lng = payload.longitude || payload.lng || 0;

          if (lat === 0 && lng === 0) return;

          const existingMarker = markers.get(eventSensorId);
          if (existingMarker) {
            existingMarker.setLngLat([lng, lat]);
            updateTrail(eventSensorId, lng, lat);
          }
        }
      }
    };

    window.addEventListener(
      "composite-measurement-event",
      handleCompositeMeasurement as EventListener
    );

    window.addEventListener(
      "accumulator-data-event",
      handleAccumulatorEvent as EventListener
    );

    window.addEventListener('resize', handleResize);

    _cleanupListeners = () => {
      window.removeEventListener(
        "composite-measurement-event",
        handleCompositeMeasurement as EventListener
      );
      window.removeEventListener(
        "accumulator-data-event",
        handleAccumulatorEvent as EventListener
      );
      window.removeEventListener('resize', handleResize);
    };
  });

  function handleResize() {
    if (map) {
      map.resize();
    }
  }

  function clearTrails() {
    if (!map) return;

    trails.forEach((_, sensorId) => {
      const sourceId = `trail-${sensorId}`;
      const layerId = `trail-line-${sensorId}`;
      if (map!.getLayer(layerId)) {
        map!.removeLayer(layerId);
      }
      if (map!.getSource(sourceId)) {
        map!.removeSource(sourceId);
      }
    });
    trails.clear();
  }

  function centerOnSensor(sensorId: string) {
    const marker = markers.get(sensorId);
    if (marker && map) {
      const lngLat = marker.getLngLat();
      map.flyTo({
        center: [lngLat.lng, lngLat.lat],
        zoom: 15,
        duration: 1000
      });
    }
  }

  onDestroy(() => {
    _cleanupListeners?.();
    _cleanupListeners = null;
    if (map) {
      map.remove();
      map = null;
    }
  });
</script>

<div class="composite-map-container">
  <div bind:this={mapContainer} class="map-element"></div>

  <div class="controls">
    <button class="control-btn" onclick={() => fitBoundsToPositions()} title="Fit all markers">
      🎯
    </button>
    {#if showTrails}
      <button class="control-btn" onclick={() => clearTrails()} title="Clear trails">
        🧹
      </button>
    {/if}
  </div>

  <div class="legend">
    <div class="legend-header">
      <span class="legend-title">Sensors ({positions.length})</span>
    </div>
    <div class="legend-items">
      {#each positions as position (position.sensor_id)}
        <button
          class="legend-item"
          onclick={() => centerOnSensor(position.sensor_id)}
          title="Click to center on {getDisplayName(position.sensor_id, position.username)}"
        >
          <span class="legend-color" style="background-color: {getMarkerColor(position.sensor_id)}"></span>
          <span class="legend-icon">{getModeIcon(position.mode)}</span>
          <span class="legend-label">{getDisplayName(position.sensor_id, position.username)}</span>
        </button>
      {/each}
    </div>
  </div>
</div>

<style>
  .composite-map-container {
    display: flex;
    flex-direction: column;
    width: 100%;
    height: 100%;
    min-height: 400px;
    background: rgba(31, 41, 55, 0.8);
    border-radius: 0.75rem;
    border: 1px solid rgba(75, 85, 99, 0.5);
    overflow: hidden;
    position: relative;
  }

  .map-element {
    flex: 1;
    width: 100%;
    min-height: 350px;
  }

  .controls {
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

  .legend {
    display: flex;
    flex-direction: column;
    max-height: 120px;
    background: rgba(17, 24, 39, 0.95);
    border-top: 1px solid rgba(75, 85, 99, 0.5);
  }

  .legend-header {
    padding: 0.5rem 1rem;
    border-bottom: 1px solid rgba(75, 85, 99, 0.3);
  }

  .legend-title {
    font-size: 0.75rem;
    font-weight: 600;
    color: #9ca3af;
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  .legend-items {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
    padding: 0.5rem 1rem;
    overflow-y: auto;
    max-height: 80px;
  }

  .legend-item {
    display: flex;
    align-items: center;
    gap: 0.25rem;
    padding: 0.25rem 0.5rem;
    background: rgba(55, 65, 81, 0.5);
    border: 1px solid rgba(75, 85, 99, 0.3);
    border-radius: 0.375rem;
    cursor: pointer;
    transition: all 0.2s;
  }

  .legend-item:hover {
    background: rgba(75, 85, 99, 0.5);
    border-color: rgba(107, 114, 128, 0.5);
  }

  .legend-color {
    width: 0.5rem;
    height: 0.5rem;
    border-radius: 50%;
    flex-shrink: 0;
  }

  .legend-icon {
    font-size: 0.75rem;
  }

  .legend-label {
    font-size: 0.625rem;
    color: #d1d5db;
    white-space: nowrap;
  }

  :global(.composite-map-marker) {
    cursor: pointer;
    display: flex;
    flex-direction: column;
    align-items: center;
    transition: transform 0.2s;
  }

  :global(.composite-map-marker:hover) {
    transform: scale(1.1);
  }

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

  :global(.composite-map-marker .mode-icon) {
    font-size: 1rem;
  }

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

  :global(.maplibregl-marker) {
    position: absolute !important;
    top: 0 !important;
    left: 0 !important;
  }

  :global(.maplibregl-ctrl-scale) {
    background: rgba(17, 24, 39, 0.8) !important;
    color: #d1d5db !important;
    border-color: rgba(75, 85, 99, 0.5) !important;
    font-size: 0.625rem !important;
  }
</style>
