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
    let marker: google.maps.marker.AdvancedMarkerElement;

    onMount(async () => {
        initMap();

        // map = new Map(mapElement, {
        //     center: { lat: position.lat, lng: position.lng },
        //     zoom: 8,
        // });

        // marker = new google.maps.marker.AdvancedMarkerElement({
        //     map: map,
        //     position: { lat: position.lat, lng: position.lng },
        // });
    });

    async function initMap() {
        let loader = new Loader({
            apiKey: apiKey,
            version: "beta",
        });

        await loader.load();

        //const { Map } = await loader.importLibrary("maps");

        console.log("Position: ", position);

        /*map = new google.maps.Map(document.getElementById("map"), {
            center: { lat: 37.4239163, lng: -122.0947209 },
            zoom: 17,
            mapId: "sensocto",
        });

        marker = new google.maps.marker.AdvancedMarkerElement({
            map,
            position: { lat: position.lat, lng: position.lng },
        });

        marker.addListener("click", ({ domEvent, latLng }) => {
            const { target } = domEvent;
            console.log("Map click", domEvent, latLng);
        });
    

        
        */
    }
</script>

<gmp-map class="h-10" center="{position.lat},{position.lng}" zoom="5">
    <gmp-advanced-marker position="{position.lat},{position.lng}" title="Title"
    ></gmp-advanced-marker>
</gmp-map>

<!--<div id="map" bind:this={mapElement} class="h-10" />-->
