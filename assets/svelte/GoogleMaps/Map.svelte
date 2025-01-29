<script lang="ts">
    // https://developers.google.com/maps/documentation/javascript/examples
    // https://developers.google.com/maps/documentation/javascript/error-messages#api-not-activated-map-error
    // https://console.cloud.google.com/google/maps-apis/api-list

    let map: google.maps.Map;
    let mapElement: HTMLDivElement;
    const apiKey = "AIzaSyArOZ8ptnmLk0kJWktriaa5SX2oWQUzzow";
    let marker: google.maps.Marker;

    async function initMap() {
        // Request needed libraries.
        const { Map } = (await google.maps.importLibrary(
            "maps",
        )) as google.maps.MapsLibrary;
        const { AdvancedMarkerElement } = (await google.maps.importLibrary(
            "marker",
        )) as google.maps.MarkerLibrary;

        const map = new Map(document.getElementById("map") as HTMLElement, {
            center: { lat: 37.4239163, lng: -122.0947209 },
            zoom: 14,
            mapId: "4504f8b37365c3d0",
        });

        const marker = new AdvancedMarkerElement({
            map,
            position: { lat: 37.4239163, lng: -122.0947209 },
        });
    }
    initMap();

    function initMap2() {
        const start = new google.maps.LatLng(52.5069704, 13.2846517);
        map = new google.maps.Map(mapElement, {
            // You can adjust these settings to your liking, of course
            center: start,
            zoom: 15,
            streetViewControl: false,
            clickableIcons: false,
            mapTypeControl: false,
        });
        marker = new google.maps.Marker({
            map,
            position: start,
        });
        map.addListener("click", (event: any) => {
            //when the user clicks, set the marker at the clicked position
            updatePosition(event.latLng);
        });
    }

    /*function updatePosition(latlng: google.maps.LatLng) {
        map.setCenter(latlng);
        marker.setPosition(latlng);
    }*/
</script>

<svelte:head>
    <script
        src="https://maps.googleapis.com/maps/api/js?key={apiKey}&libraries=geocoding&language=de&region=CH"
        on:load={initMap}
    ></script>
</svelte:head>

<div id="map" bind:this={mapElement} />

<style>
    #map {
        height: 500px;
        margin-top: 2em;
    }
</style>
