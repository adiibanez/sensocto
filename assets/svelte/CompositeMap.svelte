<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import * as maplibregl from "maplibre-gl";
  import "maplibre-gl/dist/maplibre-gl.css";

  let { positions = [] }: {
    positions: Array<{ sensor_id: string; lat: number; lng: number }>;
  } = $props();

  let mapContainer: HTMLDivElement;
  let map: maplibregl.Map | null = null;
  let markers: Map<string, maplibregl.Marker> = new Map();

  const MARKER_COLORS = [
    '#ef4444', '#f97316', '#eab308', '#22c55e', '#14b8a6',
    '#0ea5e9', '#6366f1', '#a855f7', '#ec4899', '#f43f5e'
  ];

  function getMarkerColor(index: number): string {
    return MARKER_COLORS[index % MARKER_COLORS.length];
  }

  function createMarkerElement(color: string, sensorId: string): HTMLDivElement {
    const el = document.createElement('div');
    el.className = 'composite-map-marker';
    el.innerHTML = `
      <svg width="24" height="36" viewBox="0 0 24 36" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path d="M12 0C5.4 0 0 5.4 0 12c0 9 12 24 12 24s12-15 12-24c0-6.6-5.4-12-12-12zm0 16c-2.2 0-4-1.8-4-4s1.8-4 4-4 4 1.8 4 4-1.8 4-4 4z" fill="${color}"/>
      </svg>
      <span class="marker-label">${sensorId}</span>
    `;
    return el;
  }

  function updateMarkers() {
    if (!map) return;

    const existingIds = new Set(markers.keys());
    const newIds = new Set(positions.map(p => p.sensor_id));

    existingIds.forEach(id => {
      if (!newIds.has(id)) {
        markers.get(id)?.remove();
        markers.delete(id);
      }
    });

    positions.forEach((position, index) => {
      if (position.lat === 0 && position.lng === 0) return;

      const existingMarker = markers.get(position.sensor_id);
      if (existingMarker) {
        existingMarker.setLngLat([position.lng, position.lat]);
      } else {
        const color = getMarkerColor(index);
        const el = createMarkerElement(color, position.sensor_id);

        const marker = new maplibregl.Marker({
          element: el,
          anchor: 'bottom'
        })
          .setLngLat([position.lng, position.lat])
          .addTo(map!);

        markers.set(position.sensor_id, marker);
      }
    });

    if (positions.length > 0) {
      const validPositions = positions.filter(p => p.lat !== 0 || p.lng !== 0);
      if (validPositions.length > 0) {
        const bounds = new maplibregl.LngLatBounds();
        validPositions.forEach(p => bounds.extend([p.lng, p.lat]));
        map.fitBounds(bounds, { padding: 50, maxZoom: 12 });
      }
    }
  }

  function initMap() {
    if (!mapContainer) return;

    const defaultCenter = positions.length > 0 && (positions[0].lat !== 0 || positions[0].lng !== 0)
      ? [positions[0].lng, positions[0].lat]
      : [0, 0];

    map = new maplibregl.Map({
      container: mapContainer,
      style: "https://demotiles.maplibre.org/style.json",
      center: defaultCenter as [number, number],
      zoom: 4,
      attributionControl: false
    });

    map.addControl(new maplibregl.NavigationControl(), 'top-right');

    map.on('load', () => {
      updateMarkers();
    });
  }

  onMount(async () => {
    await new Promise(resolve => setTimeout(resolve, 100));
    initMap();

    // Handler for composite measurement events from server via hook
    const handleCompositeMeasurement = (e: CustomEvent) => {
      const { sensor_id, attribute_id, payload } = e.detail;

      if (attribute_id === "geolocation" && map) {
        const lat = payload?.latitude || payload?.lat || 0;
        const lng = payload?.longitude || payload?.lng || 0;

        const existingMarker = markers.get(sensor_id);
        if (existingMarker && (lat !== 0 || lng !== 0)) {
          existingMarker.setLngLat([lng, lat]);
        } else if (lat !== 0 || lng !== 0) {
          const index = markers.size;
          const color = getMarkerColor(index);
          const el = createMarkerElement(color, sensor_id);

          const marker = new maplibregl.Marker({
            element: el,
            anchor: 'bottom'
          })
            .setLngLat([lng, lat])
            .addTo(map!);

          markers.set(sensor_id, marker);
        }
      }
    };

    // Handler for accumulator events (legacy, from sensor tiles)
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

          const existingMarker = markers.get(eventSensorId);
          if (existingMarker && (lat !== 0 || lng !== 0)) {
            existingMarker.setLngLat([lng, lat]);
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

    return () => {
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

  onDestroy(() => {
    if (map) {
      map.remove();
    }
  });
</script>

<div class="composite-map-container">
  <div bind:this={mapContainer} class="map-element"></div>
  <div class="legend">
    {#each positions as position, index (position.sensor_id)}
      <div class="legend-item">
        <span class="legend-color" style="background-color: {getMarkerColor(index)}"></span>
        <span class="legend-label">{position.sensor_id}</span>
      </div>
    {/each}
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
  }

  .map-element {
    flex: 1;
    width: 100%;
    min-height: 350px;
  }

  .legend {
    display: flex;
    flex-wrap: wrap;
    gap: 0.75rem;
    padding: 0.75rem 1rem;
    background: rgba(17, 24, 39, 0.9);
    border-top: 1px solid rgba(75, 85, 99, 0.5);
  }

  .legend-item {
    display: flex;
    align-items: center;
    gap: 0.375rem;
  }

  .legend-color {
    width: 0.75rem;
    height: 0.75rem;
    border-radius: 50%;
  }

  .legend-label {
    font-size: 0.75rem;
    color: #9ca3af;
  }

  :global(.composite-map-marker) {
    cursor: pointer;
    display: flex;
    flex-direction: column;
    align-items: center;
  }

  :global(.composite-map-marker svg) {
    filter: drop-shadow(0 2px 4px rgba(0, 0, 0, 0.3));
  }

  :global(.composite-map-marker .marker-label) {
    font-size: 0.625rem;
    color: white;
    background: rgba(0, 0, 0, 0.7);
    padding: 0.125rem 0.375rem;
    border-radius: 0.25rem;
    margin-top: 0.125rem;
    white-space: nowrap;
  }

  :global(.maplibregl-marker) {
    position: absolute !important;
    top: 0 !important;
    left: 0 !important;
  }
</style>
