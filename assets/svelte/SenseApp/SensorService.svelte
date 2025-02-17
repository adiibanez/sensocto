<script type="ts">
    import { setContext, onMount } from "svelte";
    import { Socket } from "phoenix";
    import { getCookie, setCookie } from "../utils.js";

    import { logger } from "../logger_svelte.js";
    let loggerCtxName = "SensorService";

    export let socket; // Make socket a prop so it can be shared
    let sensorChannels = {};
    let channelAttributes = {}; // Track attributes per channel
    let messageQueues = {};
    let batchTimeouts = {};
    let messagesSent = {};

    let sharedAttributes = {
        imu: {
            attribute_id: "imu",
            attribute_type: "imu",
            sampling_rate: 5,
        },
        geolocation: {
            attribute_id: "geolocation",
            attribute_type: "geolocation",
            sampling_rate: 1,
        },
        battery: {
            attribute_id: "battery",
            attribute_type: "battery",
            sampling_rate: 1,
        },
    };

    export let defaultBatchSize = 10;
    export let defaultBatchTimeout = 1000 / 24;

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
    });

    onMount(() => {
        if (socket == null) {
            socket = new Socket("/socket", {
                params: { user_token: "some_token" },
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
                //attributes: sharedAttributes,
                //attributes: {},
                //[attributeMetadata.attribute_id]: attributeMetadata,
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
            logger.warn(loggerCtxName, "socket is null", sensorId);
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
            bearer_token: "fake",
        });

        channel
            .join()
            .receive("ok", (resp) =>
                logger.log(loggerCtxName, `Joined ${fullChannelName}`, resp),
            )
            .receive("error", (resp) =>
                logger.log(
                    loggerCtxName,
                    `Error joining ${fullChannelName}`,
                    resp,
                ),
            );

        sensorChannels[fullChannelName] = channel;
        messageQueues[fullChannelName] = [];
        batchTimeouts[fullChannelName] = null;

        channel.batchSize = defaultBatchSize;
        channel.batchTimeout = defaultBatchTimeout;

        return channel;
    }

    function sendChannelMessage(sensorId, message) {
        let fullChannelName = getFullChannelName(sensorId);
        console.log(
            "sendChannelMessage",
            sensorId,
            sensorChannels.length,
            sensorChannels,
            sensorChannels[fullChannelName],
            message,
        );

        sensorChannels[fullChannelName].push("measurement", message);
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
        let deviceId = getCookie("device_id");
        if (!deviceId) {
            deviceId = uuidv4().split("-").pop();
            setCookie("device_id", deviceId);
        }
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
