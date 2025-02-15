<script lang="ts">
    // https://developers.google.com/maps/documentation/javascript/examples
    // https://developers.google.com/maps/documentation/javascript/error-messages#api-not-activated-map-error
    // https://console.cloud.google.com/google/maps-apis/api-list

    import { onMount, afterUpdate } from "svelte";

    export let position: { lat: number; lng: number; altitude: number };

    import { Loader } from "@googlemaps/js-api-loader";

    let map: google.maps.Map;
    let mapElement: HTMLDivElement;
    const apiKey = "AIzaSyArOZ8ptnmLk0kJWktriaa5SX2oWQUzzow";
    let marker: google.maps.Marker;

    onMount(async () => {
        let loader = new Loader({
            apiKey: apiKey,
            version: "weekly",
        });

        await loader.load();

        const { Map } = await loader.importLibrary("maps");

        console.log("Position: ", position);

        map = new Map(mapElement, {
            center: { lat: position.lat, lng: position.lng },
            zoom: 8,
        });

        marker = new google.maps.Marker({
            map: map,
            position: { lat: position.lat, lng: position.lng },
        });
    });
</script>

<div id="map" bind:this={mapElement} class="h-10" />
