<script lang="ts">
    // https://developers.google.com/maps/documentation/javascript/examples
    // https://developers.google.com/maps/documentation/javascript/error-messages#api-not-activated-map-error
    // https://console.cloud.google.com/google/maps-apis/api-list

    import { onMount, afterUpdate } from "svelte";

    export let position: { lat: number; lng: number; accuracy: number };
    export let identifier = "map";
    export let live = null;
    let mapContainer = null;
    let map = null;
    let marker = null;

    $: if (position) {
        if (mapContainer !== null) {
            updateMap();
        }
    }

    onMount(async () => {
        console.log(live);
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

    function updateMap() {
        /*marker.setLatLng([position.lat, position.lng]);

        var circle = L.circle([position.lat, position.lng], {
            color: "red",
            fillColor: "#f03",
            fillOpacity: 0.5,
            radius: position.accuracy / 2,
        }).addTo(map);*/

        map.setView([position.lat, position.lng], 4); // , map.getZoom()
    }

    function initMap() {
        map = L.map(identifier).setView([position.lat, position.lng], 50); // altitude
        //marker = L.marker([position.lat, position.lng]).addTo(map);
        //L.tileLayer("").addTo(map);

        updateMap();
    }

    // import { Loader } from "@googlemaps/js-api-loader";

    // let map: google.maps.Map;
    // let mapElement: HTMLDivElement;
    // const apiKey = "AIzaSyArOZ8ptnmLk0kJWktriaa5SX2oWQUzzow";
    // let marker: google.maps.marker.AdvancedMarkerElement;

    // let positionString = null;

    // $: if (position) {
    //     positionString = "{position.lat},{position.lng}";
    // }

    // onMount(async () => {
    //     initMap();

    //     // map = new Map(mapElement, {
    //     //     center: { lat: position.lat, lng: position.lng },
    //     //     zoom: 8,
    //     // });

    //     // marker = new google.maps.marker.AdvancedMarkerElement({
    //     //     map: map,
    //     //     position: { lat: position.lat, lng: position.lng },
    //     // });
    // });

    // async function initMap() {
    //     let loader = new Loader({
    //         apiKey: apiKey,
    //         version: "beta",
    //     });

    //     await loader.load();

    //     //const { Map } = await loader.importLibrary("maps");

    //     console.log("Position: ", position);

    //     /*map = new google.maps.Map(document.getElementById("map"), {
    //         center: { lat: 37.4239163, lng: -122.0947209 },
    //         zoom: 17,
    //         mapId: "sensocto",
    //     });

    //     marker = new google.maps.marker.AdvancedMarkerElement({
    //         map,
    //         position: { lat: position.lat, lng: position.lng },
    //     });

    //     marker.addListener("click", ({ domEvent, latLng }) => {
    //         const { target } = domEvent;
    //         console.log("Map click", domEvent, latLng);
    //     });

    //     */
    // }
</script>

Test {JSON.stringify(position)}
<div bind:this={mapContainer} id={identifier} class="h-20"></div>
<!--<gmp-map class="h-10" center="{position.lat},{position.lng}" zoom="5">
    <gmp-advanced-marker bind:position={positionString} title="Title"
    ></gmp-advanced-marker>
</gmp-map>-->

<!--<div id="map" bind:this={mapElement} class="h-10" />-->
