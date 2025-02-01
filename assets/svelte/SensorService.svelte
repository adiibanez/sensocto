<script type="ts">
    import { setContext, onMount } from "svelte";
    import { Socket } from "phoenix";
    import { getCookie, setCookie } from "./utils.js";

    import { logger } from "./logger_svelte.js";
    let loggerCtxName = "SensorService";

    export let socket; // Make socket a prop so it can be shared
    export let sensorChannels = {};
    let messageQueues = {};
    let batchTimeouts = {};
    let messagesSent = {};

    // Default batch size and timeout
    export let defaultBatchSize = 10;
    export let defaultBatchTimeout = 1000 / 24; // perception 24fps

    setContext("sensorService", {
        setupChannel,
        sendChannelMessage,
        leaveChannel,
        updateBatchConfig,
        getDeviceId,
    });

    onMount(() => {
        // Initialize socket connection here

        if (socket == null) {
            socket = new Socket("/socket", {
                params: { user_token: "some_token" },
            });
            socket.connect();
            logger.log(
                loggerCtxName,
                "Socket was null, initialize socket in SensorService",
            );
        }
    });

    function getDeviceId() {
        let device_id = getCookie("device_id");

        if (device_id == null || device_id === "") {
            device_id = crypto.randomUUID();
            setCookie("device_id", device_id, 365);
            logger.log(loggerCtxName, "new device_id cookie set: " + device_id);
        }

        return device_id.split("-")[0];
    }

    function getFullChannelName(sensorId) {
        return "sensor_data:" + sensorId;
    }

    function setupChannel(
        sensorId,
        metadata = {},
        batchSize = defaultBatchSize,
        batchTimeout = defaultBatchTimeout,
    ) {
        if (socket == null) {
            logger.warn(loggerCtxName, "socket is null", sensorId);
            return false;
        }

        let fullChannelName = getFullChannelName(sensorId);
        logger.log(
            loggerCtxName,
            `setupChannel ${sensorId} ${fullChannelName}`,
        );

        const channel = socket.channel(fullChannelName, {
            connector_id: getDeviceId(),
            connector_name: getDeviceName(),
            sensor_name: metadata.sensor_name,
            sensor_id: metadata.sensor_id,
            sensor_type: metadata.sensor_type,
            sampling_rate: metadata.sampling_rate,
            batch_size: 1,
            bearer_token: "fake",
        });

        logger.log(
            loggerCtxName,
            `Joining channel ${fullChannelName}`,
            metadata,
        );

        channel
            .join()
            .receive("ok", (resp) =>
                logger.log(loggerCtxName, `Joined sensor ${sensorId}`, resp),
            )
            .receive("error", (resp) =>
                logger.log(
                    loggerCtxName,
                    `Error joining sensor ${sensorId}`,
                    resp,
                ),
            );

        // Store the channel in the sensorChannels object
        sensorChannels[fullChannelName] = channel;

        // Initialize message queue and timeout for the channel
        messageQueues[fullChannelName] = [];
        batchTimeouts[fullChannelName] = null;

        // Store batch size and timeout for the channel
        channel.batchSize = batchSize;
        channel.batchTimeout = batchTimeout;

        // Listen for events from the sensor channel
        channel.on("ingest", (payload) => {
            logger.log(
                loggerCtxName,
                `Received data from ${sensorId}:`,
                payload,
            );
        });

        return channel;
    }

    function sendChannelMessage(sensorId, message) {
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
                "Flushing messages for ${channelName}",
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

    function getDeviceName() {
        return getDeviceId();
    }
</script>

<slot></slot>
