<script lang="ts">
    import { onMount, afterUpdate } from "svelte";
    import * as maplibregl from "maplibre-gl";
    import "maplibre-gl/dist/maplibre-gl.css";

    export let position: { lat: number; lng: number; accuracy: number };
    export let identifier = "map";
    export let live = null;
    let mapContainer = null;
    let map = null;
    let marker = null;

    $: {
        // Use a reactive statement to trigger updates
        if (position && map && marker) {
            console.log("Updating map and marker:", position);
            map.setCenter([position.lng, position.lat]);
            marker.setLngLat([position.lng, position.lat]);
        }
    }

    onMount(async () => {
        console.log(live);
        initMap();

        //window.addEventListener("resize", handleResizeEnd);
        window.addEventListener("resizeend", handleResizeEnd);
    });

    function handleResizeEnd(e) {
        console.log("handleResizeEnd", e);
        map.setCenter([position.lng, position.lat]);
    }

    function initMap() {
        map = new maplibregl.Map({
            container: identifier,
            style: "https://demotiles.maplibre.org/style.json", // style URL
            center: [position.lng, position.lat], // starting position [lng, lat]
            zoom: 12,
        });

        // Create marker with anchor at bottom to properly position the pin point
        marker = new maplibregl.Marker({ anchor: "bottom" })
            .setLngLat([position.lng, position.lat])
            .addTo(map);
    }
</script>

<!--Pos: {JSON.stringify(position)}-->
<div bind:this={mapContainer} id={identifier} class="map-container"></div>

<style>
    .map-container {
        width: 100%;
        height: 150px; /* Fixed height for map - MapLibre overrides Tailwind classes */
        position: relative; /* Important for marker positioning */
    }
</style>
