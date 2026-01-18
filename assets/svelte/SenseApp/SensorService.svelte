<script lang="ts">
    import { setContext, onMount } from "svelte";
    import { Socket } from "phoenix";
    import { getCookie, setCookie, getSessionValue, setSessionValue } from "../utils.js";
    import { usersettings } from "./stores.js";

    import { logger } from "../logger_svelte.js";
    let loggerCtxName = "SensorService";

    let socketState = "disconnected";
    let stateCallbacks = {
        ready: new Set(),
        disconnected: new Set(),
        error: new Set(),
    };

    export let socket;

    let sensorChannels = {};
    let channelStates = {}; // Track channel states: 'joining', 'joined', 'error', 'closed'
    let channelAttributes = {};
    let messageQueues = {};
    let batchTimeouts = {};
    let messagesSent = {};

    export let defaultBatchSize = 10;
    export let defaultBatchTimeout = 1000 / 24;
    export let bearerToken = null;

    setContext("sensorService", {
        setupChannel,
        registerAttribute,
        unregisterAttribute,
        sendChannelMessage,
        leaveChannel,
        leaveChannelIfUnused,
        updateBatchConfig,
        getDeviceId,
        getDeviceName,
        setDeviceName,
        onSocketReady: (callback) => {
            stateCallbacks.ready.add(callback);
            if (socketState === "ready") {
                callback();
            }
            return () => stateCallbacks.ready.delete(callback);
        },
        onSocketDisconnected: (callback) => {
            stateCallbacks.disconnected.add(callback);
            if (socketState === "disconnected") {
                callback();
            }
            return () => stateCallbacks.disconnected.delete(callback);
        },
        onSocketError: (callback) => {
            stateCallbacks.error.add(callback);
            return () => stateCallbacks.error.delete(callback);
        },
        getChannelState: (sensorId) => {
            const fullChannelName = getFullChannelName(sensorId);
            return channelStates[fullChannelName] || 'unknown';
        },
        isChannelReady: (sensorId) => {
            const fullChannelName = getFullChannelName(sensorId);
            return channelStates[fullChannelName] === 'joined';
        },
    });

    onMount(() => {
        if (socket == null) {
            socket = new Socket("/socket", {
                params: { user_token: "some_token" },
            });

            socket.onOpen(() => {
                socketState = "ready";
                stateCallbacks.ready.forEach((cb) => cb());
            });

            socket.onClose(() => {
                socketState = "disconnected";
                // Mark all channels as closed
                Object.keys(channelStates).forEach(ch => {
                    channelStates[ch] = 'closed';
                });
                stateCallbacks.disconnected.forEach((cb) => cb());
            });

            socket.onError((error) => {
                logger.warn(loggerCtxName, "Socket error", error);
                socketState = "error";
                stateCallbacks.error.forEach((cb) => cb(error));
            });

            socket.connect();
            logger.log(loggerCtxName, "Socket initialized");
        }
    });

    function getFullChannelName(sensorId) {
        return "sensocto:sensor:" + sensorId;
    }

    // New function to register an attribute with a channel
    function registerAttribute(sensorId, attributeMetadata) {
        const fullChannelName = getFullChannelName(sensorId);

        // Initialize channel attributes tracking if needed
        if (!channelAttributes[fullChannelName]) {
            channelAttributes[fullChannelName] = new Set();
        }

        // Add this attribute to the channel
        channelAttributes[fullChannelName].add(attributeMetadata.attribute_id);
        logger.log(
            loggerCtxName,
            `Registered attribute ${attributeMetadata.attribute_id} to ${fullChannelName}`,
        );

        // If channel doesn't exist, create it
        if (!sensorChannels[fullChannelName]) {
            return setupChannel(sensorId, {
                sensor_name: attributeMetadata.sensor_name || sensorId,
                sensor_id: sensorId,
                sensor_type: attributeMetadata.sensor_type,
                sampling_rate: attributeMetadata.sampling_rate,
            });
        }
        // Update existing channel's attributes
        const channel = sensorChannels[fullChannelName];
        channel.push("update_attributes", {
            action: "register",
            attribute_id: attributeMetadata.attribute_id,
            metadata: attributeMetadata,
        });
        return channel;
    }

    // New function to unregister an attribute from a channel
    function unregisterAttribute(sensorId, attributeId) {
        const fullChannelName = getFullChannelName(sensorId);

        if (channelAttributes[fullChannelName]) {
            channelAttributes[fullChannelName].delete(attributeId);
            logger.log(
                loggerCtxName,
                `Unregistered attribute ${attributeId} from ${fullChannelName}`,
            );

            // If no attributes left, leave the channel
            if (channelAttributes[fullChannelName].size === 0) {
                leaveChannelIfUnused(sensorId);
            } else {
                // Notify server about attribute removal
                sensorChannels[fullChannelName]?.push("update_attributes", {
                    action: "unregister",
                    attribute_id: attributeId,
                    metadata: {},
                });
            }
        }
    }

    function leaveChannelIfUnused(sensorId) {
        const fullChannelName = getFullChannelName(sensorId);

        if (channelAttributes[fullChannelName]?.size === 0) {
            if (sensorChannels[fullChannelName]) {
                sensorChannels[fullChannelName].leave();
                delete sensorChannels[fullChannelName];
                delete channelStates[fullChannelName];
                delete channelAttributes[fullChannelName];
                delete messageQueues[fullChannelName];
                delete batchTimeouts[fullChannelName];
                delete messagesSent[fullChannelName];
                logger.log(
                    loggerCtxName,
                    `Channel ${fullChannelName} closed - no active attributes`,
                );
            }
        }
    }

    // ... existing helper functions (getDeviceId, etc.) ...

    function setupChannel(
        sensorId,
        metadata = {
            sensor_id: getDeviceId(),
            sensor_name: getDeviceName(),
            sensor_type: "html5",
            sampling_rate: 1,
        },
    ) {
        if (!socket) {
            logger.warn(loggerCtxName, "socket is null - cannot setup channel", sensorId);
            return false;
        }

        // Check if socket is connected
        if (!socket.isConnected()) {
            logger.warn(loggerCtxName, "socket not connected - cannot setup channel", sensorId);
            return false;
        }

        const fullChannelName = getFullChannelName(sensorId);

        if (
            sensorChannels[fullChannelName] &&
            sensorChannels[fullChannelName].state == "joined"
        ) {
            console.log("Reuse channel", sensorChannels[fullChannelName]);
            return sensorChannels[fullChannelName];
        }

        const channel = socket.channel(fullChannelName, {
            connector_id: getDeviceId(),
            connector_name: getDeviceName(),
            ...metadata,
            attributes: metadata.attributes || {},
            batch_size: 1,
            bearer_token: bearerToken || "missing",
        });

        // Track channel state
        channelStates[fullChannelName] = 'joining';

        channel
            .join()
            .receive("ok", (resp) => {
                channelStates[fullChannelName] = 'joined';
                logger.log(loggerCtxName, `Joined ${fullChannelName}`, resp);
                // Flush any messages that were queued while joining
                if (messageQueues[fullChannelName]?.length > 0) {
                    logger.log(loggerCtxName, `Flushing ${messageQueues[fullChannelName].length} queued messages for ${fullChannelName}`);
                    const queuedMessages = [...messageQueues[fullChannelName]];
                    messageQueues[fullChannelName] = [];
                    queuedMessages.forEach(msg => {
                        channel.push("measurement", msg);
                    });
                }
            })
            .receive("error", (resp) => {
                channelStates[fullChannelName] = 'error';
                logger.warn(
                    loggerCtxName,
                    `Error joining ${fullChannelName}`,
                    resp,
                );
            })
            .receive("timeout", () => {
                channelStates[fullChannelName] = 'timeout';
                logger.warn(
                    loggerCtxName,
                    `Timeout joining ${fullChannelName} - server may be unreachable`,
                );
            });

        // Handle channel errors after join
        channel.onError((err) => {
            channelStates[fullChannelName] = 'error';
            logger.warn(loggerCtxName, `Channel error for ${fullChannelName}`, err);
        });

        // Handle channel close
        channel.onClose(() => {
            channelStates[fullChannelName] = 'closed';
            logger.log(loggerCtxName, `Channel closed: ${fullChannelName}`);
        });

        sensorChannels[fullChannelName] = channel;
        messageQueues[fullChannelName] = [];
        batchTimeouts[fullChannelName] = null;

        channel.batchSize = defaultBatchSize;
        channel.batchTimeout = defaultBatchTimeout;

        return channel;
    }

    function sendChannelMessage(sensorId, message) {
        let fullChannelName = getFullChannelName(sensorId);
        const channel = sensorChannels[fullChannelName];
        const channelState = channelStates[fullChannelName];

        // Check if channel exists and is in a valid state
        if (!channel) {
            logger.warn(loggerCtxName, `Cannot send message - channel not found: ${fullChannelName}`);
            return false;
        }

        if (channelState !== 'joined') {
            logger.warn(
                loggerCtxName,
                `Cannot send message - channel not ready: ${fullChannelName}, state: ${channelState}`,
            );
            // Queue message for later if channel is still joining
            if (channelState === 'joining') {
                if (!messageQueues[fullChannelName]) {
                    messageQueues[fullChannelName] = [];
                }
                messageQueues[fullChannelName].push(message);
                logger.log(loggerCtxName, `Message queued for ${fullChannelName}, queue size: ${messageQueues[fullChannelName].length}`);
            }
            return false;
        }

        logger.log(
            loggerCtxName,
            "sendChannelMessage",
            sensorId,
            message,
        );

        channel.push("measurement", message);
        return true;
    }

    function _sendChannelMessage(sensorId, message) {
        let fullChannelName = getFullChannelName(sensorId);
        logger.log(loggerCtxName, `sendChannelMessage ${sensorId}`, message);

        // Add message to the queue
        if (!messageQueues[fullChannelName]) {
            messageQueues[fullChannelName] = [];
        }

        if (messagesSent[fullChannelName] === undefined) {
            messagesSent[fullChannelName] = 0;
        }

        messageQueues[fullChannelName].push(message);

        // Get batch size and timeout for the channel
        let batchSize =
            sensorChannels[fullChannelName].batchSize || defaultBatchSize;
        let batchTimeout =
            sensorChannels[fullChannelName].batchTimeout || defaultBatchTimeout;

        logger.log(
            loggerCtxName,
            `Queue length: ${messageQueues[fullChannelName].length}, Batch size: ${batchSize}`,
        );

        // Check if the batch size is reached, or if we send the first message
        if (
            messagesSent[fullChannelName] == 0 ||
            messageQueues[fullChannelName].length >= batchSize
        ) {
            flushMessages(fullChannelName);
        } else {
            // Schedule a batch timeout if not already scheduled
            if (!batchTimeouts[fullChannelName]) {
                batchTimeouts[fullChannelName] = setTimeout(() => {
                    flushMessages(fullChannelName);
                }, batchTimeout);
                logger.log(
                    loggerCtxName,
                    `Scheduled batch timeout for ${fullChannelName}`,
                );
            }
        }
    }

    function flushMessages(channelName) {
        if (
            messageQueues[channelName] &&
            messageQueues[channelName].length > 0
        ) {
            messagesSent[channelName] += messageQueues[channelName].length;

            logger.log(
                loggerCtxName,
                "Flushing messages for ",
                channelName,
                sensorChannels[channelName],
                messageQueues[channelName],
                messageQueues[channelName].length,
                messagesSent[channelName],
            );

            if (messageQueues[channelName].length == 1) {
                sensorChannels[channelName].push(
                    "measurement",
                    messageQueues[channelName].pop(),
                );
            } else {
                sensorChannels[channelName].push(
                    "measurements_batch",
                    messageQueues[channelName],
                );
            }

            // Clear the queue and timeout
            messageQueues[channelName] = [];
            clearTimeout(batchTimeouts[channelName]);
            batchTimeouts[channelName] = null;
        }
    }

    function leaveChannel(sensorId) {
        logger.log(loggerCtxName, `Leaving channel for sensor ${sensorId}`);
        var channel = sensorChannels[getFullChannelName(sensorId)];

        if (channel) {
            sensorChannels[getFullChannelName(sensorId)].leave();
        }
    }

    function updateBatchConfig(sensorId, newBatchSize, newBatchTimeout) {
        let fullChannelName = getFullChannelName(sensorId);
        if (sensorChannels[fullChannelName]) {
            sensorChannels[fullChannelName].batchSize = newBatchSize;
            sensorChannels[fullChannelName].batchTimeout = newBatchTimeout;
            logger.log(
                loggerCtxName,
                `Updated batch config for ${sensorId}: batchSize=${newBatchSize}, batchTimeout=${newBatchTimeout}`,
            );
        } else {
            logger.warn(
                loggerCtxName,
                `Channel for sensor ${sensorId} not found`,
            );
        }
    }

    import { v4 as uuidv4 } from "uuid";

    function getDeviceId() {
        // Use sessionStorage for device_id so each tab gets its own unique ID
        // This prevents conflicts when multiple tabs are open
        let deviceId = getSessionValue("device_id");
        if (!deviceId) {
            deviceId = uuidv4().split("-").pop();
            setSessionValue("device_id", deviceId);
        }
        $usersettings.deviceId = deviceId;
        return deviceId;
    }

    export function getDeviceName() {
        let deviceName = getCookie("device_name");
        if (!deviceName) {
            let platform = navigator.platform || "unknown_platform";
            let browserName =
                navigator.userAgent.match(
                    /(firefox|msie|chrome|safari|trident)/gi,
                )?.[0] || "unknown_browser";
            deviceName = `${platform}_${browserName}`; // _${getDeviceId()

            $usersettings.deviceName = deviceName;
            setCookie("device_name", deviceName);
        }
        return deviceName;
    }

    export function setDeviceName(deviceName) {
        if (deviceName) {
            setCookie("device_name", deviceName);
        }
    }
</script>

<slot></slot>
