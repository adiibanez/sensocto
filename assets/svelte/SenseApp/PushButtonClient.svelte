<script>
    import { getContext, onDestroy, onMount } from "svelte";
    import { isMobile } from "../utils.js";

    let sensorService = getContext("sensorService");
    let channelIdentifier = sensorService.getDeviceId();

    var channel = null;
    let unsubscribeSocket;

    // Track currently pressed buttons (for visual feedback and simultaneous presses)
    let pressedButtons = new Set();

    // Detect mobile/tablet - these get direct tap behavior
    // Desktop gets keyboard shortcuts (number keys work without modifiers)
    let mobile = false;

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

    // Keyboard handling - number keys work directly (no Space modifier needed)
    const handleKeyDown = (event) => {
        // Don't capture when typing in inputs
        if (event.target.tagName === 'INPUT' || event.target.tagName === 'TEXTAREA') {
            return;
        }
        // Ignore key repeat
        if (event.repeat) return;

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

    // Unified press/release
    const pressButton = (buttonId) => {
        if (!pressedButtons.has(buttonId)) {
            pressedButtons.add(buttonId);
            pressedButtons = pressedButtons;
            sendButtonPress(buttonId);
        }
    };

    const releaseButton = (buttonId) => {
        if (pressedButtons.has(buttonId)) {
            pressedButtons.delete(buttonId);
            pressedButtons = pressedButtons;
            sendButtonRelease(buttonId);
        }
    };

    // Release all buttons (safety for edge cases)
    const releaseAllButtons = () => {
        pressedButtons.forEach(buttonId => {
            sendButtonRelease(buttonId);
        });
        pressedButtons.clear();
        pressedButtons = pressedButtons;
    };

    // Handle visibility change (tab switching) - more reliable than blur
    const handleVisibilityChange = () => {
        if (document.hidden) {
            releaseAllButtons();
        }
    };

    // Clear any stuck buttons from previous sessions (server might have stale state)
    const resetAllButtons = () => {
        for (let i = 1; i <= 8; i++) {
            sendButtonRelease(i);
        }
    };

    // Svelte action to add non-passive touch listeners (required for Safari iPad)
    function buttonAction(node, buttonId) {
        const onTouchStart = (e) => {
            e.preventDefault();
            pressButton(buttonId);
        };

        const onTouchEnd = (e) => {
            e.preventDefault();
            releaseButton(buttonId);
        };

        const onTouchCancel = () => {
            releaseButton(buttonId);
        };

        const onMouseDown = (e) => {
            e.preventDefault();
            pressButton(buttonId);
        };

        const onMouseUp = () => {
            releaseButton(buttonId);
        };

        const onMouseLeave = () => {
            releaseButton(buttonId);
        };

        // Add touch listeners with { passive: false } to allow preventDefault on Safari
        node.addEventListener('touchstart', onTouchStart, { passive: false });
        node.addEventListener('touchend', onTouchEnd, { passive: false });
        node.addEventListener('touchcancel', onTouchCancel, { passive: false });

        // Mouse events for desktop
        node.addEventListener('mousedown', onMouseDown);
        node.addEventListener('mouseup', onMouseUp);
        node.addEventListener('mouseleave', onMouseLeave);

        return {
            update(newButtonId) {
                buttonId = newButtonId;
            },
            destroy() {
                node.removeEventListener('touchstart', onTouchStart);
                node.removeEventListener('touchend', onTouchEnd);
                node.removeEventListener('touchcancel', onTouchCancel);
                node.removeEventListener('mousedown', onMouseDown);
                node.removeEventListener('mouseup', onMouseUp);
                node.removeEventListener('mouseleave', onMouseLeave);
            }
        };
    }

    onMount(() => {
        mobile = isMobile();

        // Wait for socket to be ready before registering the button attribute
        unsubscribeSocket = sensorService.onSocketReady(() => {
            ensureChannel();
            // Clear any stuck state from previous sessions after channel is ready
            setTimeout(resetAllButtons, 100);
        });

        // Keyboard listeners for number key shortcuts
        window.addEventListener('keydown', handleKeyDown);
        window.addEventListener('keyup', handleKeyUp);

        // Safety: release all buttons on focus loss
        window.addEventListener('blur', releaseAllButtons);
        // More reliable for tab switches
        document.addEventListener('visibilitychange', handleVisibilityChange);
        // Handles navigation away
        window.addEventListener('pagehide', releaseAllButtons);
    });

    onDestroy(() => {
        if (unsubscribeSocket) {
            unsubscribeSocket();
        }
        window.removeEventListener('keydown', handleKeyDown);
        window.removeEventListener('keyup', handleKeyUp);
        window.removeEventListener('blur', releaseAllButtons);
        document.removeEventListener('visibilitychange', handleVisibilityChange);
        window.removeEventListener('pagehide', releaseAllButtons);

        // Clean up any pressed buttons
        releaseAllButtons();

        sensorService.unregisterAttribute(sensorService.getDeviceId(), "button");
        sensorService.leaveChannelIfUnused(channelIdentifier);
    });

    const getButtonStyle = (button, isPressed) => {
        return isPressed ? button.hoverStyle : button.style;
    };
</script>

<div class="flex gap-1 flex-wrap items-center">
    {#each buttons as button}
        <button
            class="push-button w-8 h-8 rounded text-white text-sm font-bold flex items-center justify-center"
            class:pressed={pressedButtons.has(button.id)}
            style={getButtonStyle(button, pressedButtons.has(button.id))}
            use:buttonAction={button.id}
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
        touch-action: manipulation;
        -webkit-tap-highlight-color: transparent;
    }
    .push-button:active {
        transform: scale(0.92);
    }
    .push-button.pressed {
        transform: scale(0.92);
        filter: brightness(0.85);
    }
</style>
