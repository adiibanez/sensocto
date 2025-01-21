<script type="ts">
    import {setContext, onMount} from 'svelte';
    import {Socket} from "phoenix";
    import {getCookie, setCookie} from './utils.js';

    export let socket; // Make socket a prop so it can be shared
    export let sensorChannels = {};

    setContext('sensorService', {setupChannel, sendChannelMessage, leaveChannel, getDeviceId});

    onMount(() => {
        // Initialize socket connection here

        if (socket == null) {
            socket = new Socket("/socket", {params: {user_token: "some_token"}});
            socket.connect();
            console.log('Socket was null, initialize socket in SensorService', socket);
        }
    });

    /*onMount(() => {
        console.log('initialize socket in SensorService', socket) 
    });*/

    function getDeviceId() {

        let device_id = getCookie('device_id');

        if (device_id == null || device_id === "") {
            device_id = crypto.randomUUID();
            setCookie('device_id', device_id, 365);
            console.log("new device_id cookie set: " + device_id);
        }

        return device_id;
    }

    function getFullChannelName(sensorId) {
        return "sensor_data:" + sensorId
    }

    function setupChannel(sensorId, metadata = {}) {

        if (socket == null) {
            console.warn('socket is null', sensorId);
            return false;
        }

        let fullChannelName = getFullChannelName(sensorId);
        console.log("setupChannel", sensorId, fullChannelName);

        console.log('setupChannel socket', socket);

        const channel = socket.channel(fullChannelName, {
            sensor_name: metadata.sensor_name,
            sensor_id: metadata.sensor_id,
            connector_id: metadata.connector_id,
            connector_name: metadata.connector_name
        });

        channel
            .join()
            .receive("ok", (resp) => console.log(`Joined sensor ${sensorId}`, resp))
            .receive("error", (resp) => console.log(`Error joining sensor ${sensorId}`, resp));

        // Store the channel in the sensorChannels object
        sensorChannels[fullChannelName] = channel;

        // Listen for events from the sensor channel
        channel.on("ingest", (payload) => {
            console.log(`Received data from ${sensorId}:`, payload);
        });
    }

    function sendChannelMessage(sensorId, message) {
        console.log("sensorId", sensorId, message);
        sensorChannels[getFullChannelName(sensorId)].push("measurement", message);
    }

    function leaveChannel(sensorId) {
        console.log(`Leaving channel for sensor ${sensorId}`);
        var channel = sensorChannels[getFullChannelName(sensorId)];

        if (channel) {
            sensorChannels[getFullChannelName(sensorId)].leave();
        }
    }

</script>


<slot></slot>