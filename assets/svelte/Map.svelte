<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import * as maplibregl from "maplibre-gl";
  import "maplibre-gl/dist/maplibre-gl.css";

  export let position: { lat: number; lng: number; accuracy: number };
  export let identifier = "map";
  export let live = null;
  let mapContainer: HTMLDivElement;
  let map: maplibregl.Map | null = null;
  let marker: maplibregl.Marker | null = null;

  $: {
    // Use a reactive statement to trigger updates
    if (position && map && marker) {
      console.log("Updating map and marker:", position);
      map.setCenter([position.lng, position.lat]);
      marker.setLngLat([position.lng, position.lat]);
    }
  }

  onMount(async () => {
    // Wait a tick for the container to be properly sized
    await new Promise((resolve) => setTimeout(resolve, 100));
    initMap();

    window.addEventListener("resize", handleResize);
  });

  onDestroy(() => {
    window.removeEventListener("resize", handleResize);
    if (map) {
      map.remove();
    }
  });

  function handleResize() {
    if (map) {
      // Trigger map resize to recalculate dimensions
      map.resize();
    }
  }

  function initMap() {
    if (!mapContainer) return;

    map = new maplibregl.Map({
      container: mapContainer,
      style: "https://demotiles.maplibre.org/style.json",
      center: [position.lng, position.lat],
      zoom: 6,
      attributionControl: false,
    });

    // Wait for map to load before adding marker
    map.on("load", () => {
      // Create a custom marker element for better control
      const el = document.createElement("div");
      el.className = "custom-marker";
      el.innerHTML = `
                <svg width="24" height="36" viewBox="0 0 24 36" fill="none" xmlns="http://www.w3.org/2000/svg">
                    <path d="M12 0C5.4 0 0 5.4 0 12c0 9 12 24 12 24s12-15 12-24c0-6.6-5.4-12-12-12zm0 16c-2.2 0-4-1.8-4-4s1.8-4 4-4 4 1.8 4 4-1.8 4-4 4z" fill="#e53e3e"/>
                </svg>
            `;

      marker = new maplibregl.Marker({
        element: el,
        anchor: "bottom",
      })
        .setLngLat([position.lng, position.lat])
        .addTo(map!);
    });
  }
</script>

<div bind:this={mapContainer} id={identifier} class="map-container"></div>

<style>
  .map-container {
    width: 100%;
    height: 100%;
    min-height: 150px;
    position: relative;
    overflow: visible;
  }

  :global(.custom-marker) {
    cursor: pointer;
  }

  :global(.custom-marker svg) {
    filter: drop-shadow(0 2px 4px rgba(0, 0, 0, 0.3));
  }

  /* Fix marker positioning - MapLibre markers need top:0 as base position */
  :global(.maplibregl-marker) {
    position: absolute !important;
    top: 0 !important;
    left: 0 !important;
  }
</style>
