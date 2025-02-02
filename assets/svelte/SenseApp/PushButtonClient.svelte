<script>
    import { getContext, onDestroy, onMount } from "svelte";

    let sensorService = getContext("sensorService");
    let channelIdentifier = sensorService.getDeviceId() + ":button";

    channel = null;

    const sendPushButtonEvent = async () => {
        if (channel === null) {
            const metadata = {
                sensor_name: channelIdentifier,
                sensor_id: channelIdentifier,
                sensor_type: "button",
                sampling_rate: 1,
            };

            channel = sensorService.setupChannel(channelIdentifier, metadata);
        }

        let payload = {
            payload: 1,
            attribute_id: channelIdentifier,
            timestamp: Math.round(new Date().getTime()),
        };
        sensorService.sendChannelMessage(channelIdentifier, payload);
    };

    onDestroy(() => {
        sensorService.leaveChannel(channelIdentifier); // Important: Leave the channel
    });
</script>

<button class="btn btn-blue text-xs" on:click={sendPushButtonEvent}
    >Send Button Pressed</button
>
