<script>
    import { getContext, onDestroy, onMount } from "svelte";

    let sensorService = getContext("sensorService");
    let channelIdentifier = sensorService.getDeviceId();

    var channel = null;

    const buttons = [
        { id: 1, color: "bg-red-500 hover:bg-red-600", label: "1" },
        { id: 2, color: "bg-green-500 hover:bg-green-600", label: "2" },
        { id: 3, color: "bg-blue-500 hover:bg-blue-600", label: "3" },
    ];

    const sendPushButtonEvent = async (buttonId) => {
        if (channel === null) {
            channel = sensorService.setupChannel(channelIdentifier);
            sensorService.registerAttribute(sensorService.getDeviceId(), {
                attribute_id: "button",
                attribute_type: "button",
                sampling_rate: 1,
            });
        }

        let payload = {
            payload: buttonId,
            attribute_id: "button",
            timestamp: Math.round(new Date().getTime()),
        };
        sensorService.sendChannelMessage(channelIdentifier, payload);
    };

    onDestroy(() => {
        sensorService.leaveChannelIfUnused(channelIdentifier, "button");
    });
</script>

<div class="flex gap-1">
    {#each buttons as button}
        <button
            class="w-6 h-6 rounded text-white text-xs font-bold {button.color} flex items-center justify-center"
            on:click={() => sendPushButtonEvent(button.id)}
        >
            {button.label}
        </button>
    {/each}
</div>
