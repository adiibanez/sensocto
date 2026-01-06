<script>
    import { getContext, onDestroy, onMount } from "svelte";
    import { isMobile } from "../utils.js";

    let sensorService = getContext("sensorService");
    let channelIdentifier = sensorService.getDeviceId();

    var channel = null;
    let unsubscribeSocket;

    // Track currently pressed buttons (for visual feedback and simultaneous presses)
    let pressedButtons = new Set();

    // Check if we're on desktop (requires Space key for buttons)
    let isDesktop = false;

    // Track if Space key is currently held down (for desktop modifier)
    let spaceKeyHeld = false;

    onMount(() => {
        isDesktop = !isMobile();
    });

    const buttons = [
        { id: 1, style: "background-color: #ef4444;", hoverStyle: "background-color: #dc2626;", label: "1", key: "1" },
        { id: 2, style: "background-color: #f97316;", hoverStyle: "background-color: #ea580c;", label: "2", key: "2" },
        { id: 3, style: "background-color: #eab308;", hoverStyle: "background-color: #ca8a04;", label: "3", key: "3" },
        { id: 4, style: "background-color: #22c55e;", hoverStyle: "background-color: #16a34a;", label: "4", key: "4" },
        { id: 5, style: "background-color: #14b8a6;", hoverStyle: "background-color: #0d9488;", label: "5", key: "5" },
        { id: 6, style: "background-color: #3b82f6;", hoverStyle: "background-color: #2563eb;", label: "6", key: "6" },
        { id: 7, style: "background-color: #6366f1;", hoverStyle: "background-color: #4f46e5;", label: "7", key: "7" },
        { id: 8, style: "background-color: #a855f7;", hoverStyle: "background-color: #9333ea;", label: "8", key: "8" },
    ];

    const keyToButtonId = {
        "1": 1, "2": 2, "3": 3, "4": 4,
        "5": 5, "6": 6, "7": 7, "8": 8
    };

    const ensureChannel = () => {
        if (channel === null) {
            channel = sensorService.setupChannel(channelIdentifier);
            sensorService.registerAttribute(sensorService.getDeviceId(), {
                attribute_id: "button",
                attribute_type: "button",
                sampling_rate: 1,
            });
        }
    };

    const sendButtonPress = (buttonId) => {
        ensureChannel();
        let payload = {
            payload: buttonId,
            attribute_id: "button",
            timestamp: Math.round(new Date().getTime()),
            event: "press"
        };
        sensorService.sendChannelMessage(channelIdentifier, payload);
    };

    const sendButtonRelease = (buttonId) => {
        ensureChannel();
        let payload = {
            payload: buttonId,
            attribute_id: "button",
            timestamp: Math.round(new Date().getTime()),
            event: "release"
        };
        sensorService.sendChannelMessage(channelIdentifier, payload);
    };

    const handleKeyDown = (event) => {
        if (event.target.tagName === 'INPUT' || event.target.tagName === 'TEXTAREA') {
            return;
        }
        if (event.repeat) return;

        // On desktop, require Space key to be held down
        if (isDesktop && !spaceKeyHeld) {
            return;
        }

        const buttonId = keyToButtonId[event.key];
        if (buttonId && !pressedButtons.has(buttonId)) {
            pressedButtons.add(buttonId);
            pressedButtons = pressedButtons;
            sendButtonPress(buttonId);
        }
    };

    const handleKeyUp = (event) => {
        const buttonId = keyToButtonId[event.key];
        if (buttonId && pressedButtons.has(buttonId)) {
            pressedButtons.delete(buttonId);
            pressedButtons = pressedButtons;
            sendButtonRelease(buttonId);
        }
    };

    const handleMouseDown = (event, buttonId) => {
        // On desktop, require Space key to be held down
        if (isDesktop && !spaceKeyHeld) {
            return;
        }

        if (!pressedButtons.has(buttonId)) {
            pressedButtons.add(buttonId);
            pressedButtons = pressedButtons;
            sendButtonPress(buttonId);
        }
    };

    const handleMouseUp = (buttonId) => {
        if (pressedButtons.has(buttonId)) {
            pressedButtons.delete(buttonId);
            pressedButtons = pressedButtons;
            sendButtonRelease(buttonId);
        }
    };

    const handleMouseLeave = (buttonId) => {
        if (pressedButtons.has(buttonId)) {
            pressedButtons.delete(buttonId);
            pressedButtons = pressedButtons;
            sendButtonRelease(buttonId);
        }
    };

    const handleSpaceDown = (event) => {
        if (event.code === 'Space' && !event.repeat) {
            event.preventDefault();
            spaceKeyHeld = true;
        }
    };

    const handleSpaceUp = (event) => {
        if (event.code === 'Space') {
            spaceKeyHeld = false;
            // Release all pressed buttons when space is released
            pressedButtons.forEach(buttonId => {
                sendButtonRelease(buttonId);
            });
            pressedButtons.clear();
            pressedButtons = pressedButtons;
        }
    };

    onMount(() => {
        // Wait for socket to be ready before registering the button attribute
        // This ensures the channel is established and the attribute shows up in the UI
        unsubscribeSocket = sensorService.onSocketReady(() => {
            ensureChannel();
        });

        window.addEventListener('keydown', handleKeyDown);
        window.addEventListener('keyup', handleKeyUp);
        window.addEventListener('keydown', handleSpaceDown);
        window.addEventListener('keyup', handleSpaceUp);
    });

    onDestroy(() => {
        if (unsubscribeSocket) {
            unsubscribeSocket();
        }
        window.removeEventListener('keydown', handleKeyDown);
        window.removeEventListener('keyup', handleKeyUp);
        window.removeEventListener('keydown', handleSpaceDown);
        window.removeEventListener('keyup', handleSpaceUp);
        sensorService.unregisterAttribute(sensorService.getDeviceId(), "button");
        sensorService.leaveChannelIfUnused(channelIdentifier);
    });

    const getButtonStyle = (button, isPressed) => {
        return isPressed ? button.hoverStyle : button.style;
    };
</script>

<div class="flex gap-1 flex-wrap items-center">
    {#if isDesktop}
        <span class="text-xs text-gray-400 font-mono mr-1" class:space-active={spaceKeyHeld}>Space +</span>
    {/if}
    {#each buttons as button}
        <button
            class="push-button w-6 h-6 rounded text-white text-xs font-bold flex items-center justify-center"
            class:pressed={pressedButtons.has(button.id)}
            style={getButtonStyle(button, pressedButtons.has(button.id))}
            on:mousedown={(e) => handleMouseDown(e, button.id)}
            on:mouseup={() => handleMouseUp(button.id)}
            on:mouseleave={() => handleMouseLeave(button.id)}
            on:touchstart|preventDefault={(e) => handleMouseDown(e, button.id)}
            on:touchend|preventDefault={() => handleMouseUp(button.id)}
            title={isDesktop ? `Hold Space + click or press '${button.key}'` : `Tap button ${button.key}`}
        >
            {button.label}
        </button>
    {/each}
</div>

<style>
    .push-button {
        cursor: pointer;
        transition: background-color 0.15s ease, transform 0.1s ease;
        user-select: none;
        -webkit-user-select: none;
    }
    .push-button.pressed {
        transform: scale(0.9);
    }
    .space-active {
        color: #22c55e;
        font-weight: bold;
    }
</style>
