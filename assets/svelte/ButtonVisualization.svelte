<script>
    import { onMount, onDestroy } from "svelte";

    export let sensor_id;
    export let attribute_id;
    export let size = "normal"; // "small" for summary mode, "normal" for full mode

    // Track currently pressed buttons
    let pressedButtons = new Set();

    // Force reactivity
    let pressedButtonsArray = [];

    const buttonColors = {
        1: "#ef4444",  // red
        2: "#f97316",  // orange
        3: "#eab308",  // yellow
        4: "#22c55e",  // green
        5: "#14b8a6",  // teal
        6: "#3b82f6",  // blue
        7: "#6366f1",  // indigo
        8: "#a855f7"   // purple
    };

    const inactiveColor = "#4b5563";
    const inactiveTextColor = "#9ca3af";

    function handleButtonEvent(event) {
        const { payload, event: eventType } = event.detail || event;
        const buttonId = parseInt(payload);

        if (isNaN(buttonId) || buttonId < 1 || buttonId > 8) return;

        if (eventType === "press") {
            pressedButtons.add(buttonId);
        } else if (eventType === "release") {
            pressedButtons.delete(buttonId);
        } else {
            // Legacy: single button press without event type
            // Treat as momentary press
            pressedButtons = new Set([buttonId]);
        }

        // Trigger reactivity
        pressedButtonsArray = Array.from(pressedButtons);
    }

    function isPressed(buttonId) {
        return pressedButtons.has(buttonId);
    }

    function getButtonStyle(buttonId) {
        if (isPressed(buttonId)) {
            return `background-color: ${buttonColors[buttonId]}; color: white; transform: scale(0.9);`;
        }
        return `background-color: ${inactiveColor}; color: ${inactiveTextColor};`;
    }

    // Listen for sensor data events
    let unsubscribe;

    onMount(() => {
        // Subscribe to the sensor data channel for this attribute
        const channelName = `data:${sensor_id}`;

        // Listen for custom events dispatched by the SensorDataAccumulator hook
        const container = document.getElementById(`cnt_${sensor_id}_${attribute_id}`) ||
                          document.getElementById(`cnt_summary_${sensor_id}_${attribute_id}`) ||
                          document.getElementById(`vibrate_${sensor_id}_${attribute_id}`);

        if (container) {
            container.addEventListener("sensor-data", (e) => {
                if (e.detail && e.detail.attribute_id === attribute_id) {
                    handleButtonEvent(e.detail);
                }
            });
        }

        // Also listen on window for broadcasted events
        window.addEventListener(`button-event-${sensor_id}-${attribute_id}`, handleButtonEvent);
    });

    onDestroy(() => {
        window.removeEventListener(`button-event-${sensor_id}-${attribute_id}`, handleButtonEvent);
    });

    // Expose method to update from parent
    export function updateButton(payload, eventType) {
        handleButtonEvent({ detail: { payload, event: eventType }});
    }

    $: buttonSize = size === "small" ? "w-4 h-4 text-[10px]" : "w-6 h-6 text-xs";
    $: gapSize = size === "small" ? "gap-0.5" : "gap-1";
</script>

<div class="flex {gapSize} flex-wrap">
    {#each [1, 2, 3, 4, 5, 6, 7, 8] as buttonId}
        <div
            class="{buttonSize} rounded font-bold flex items-center justify-center transition-all duration-100"
            style={getButtonStyle(buttonId)}
        >
            {buttonId}
        </div>
    {/each}
</div>

<style>
    div {
        user-select: none;
    }
</style>
