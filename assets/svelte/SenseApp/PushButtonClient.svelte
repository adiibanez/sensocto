<script>
    import { getContext, onDestroy, onMount } from "svelte";

    let sensorService = getContext("sensorService");
    let channelIdentifier = sensorService.getDeviceId();

    var channel = null;

    const sendPushButtonEvent = async () => {
        if (channel === null) {
            channel = sensorService.setupChannel(channelIdentifier);
            sensorService.registerAttribute(sensorService.getDeviceId(), {
                attribute_id: "button",
                attribute_type: "button",
                sampling_rate: 1,
            });
        }

        let payload = {
            payload: 1,
            attribute_id: "button",
            timestamp: Math.round(new Date().getTime()),
        };
        sensorService.sendChannelMessage(channelIdentifier, payload);
    };

    onDestroy(() => {
        sensorService.leaveChannelIfUnused(channelIdentifier, "button"); // Important: Leave the channel
    });
</script>

<button class="btn btn-blue text-xs" on:click={sendPushButtonEvent}
    >Send Button Pressed</button
>
