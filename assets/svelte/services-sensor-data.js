// sensorDataService.js
import { get, writable } from 'svelte/store';
import { logger } from "./logger.js";
import { tick } from 'svelte';

let loggerCtxName = "SensorDataService";

const sensorDataMap = writable(new Map()); // Store data per sensor

const getSensorDataStore = (identifier) => {
    logger.log(loggerCtxName, "getSensorDataStore", identifier);

    let store;
    sensorDataMap.update(map => {
        if (!map.has(identifier)) {
            map.set(identifier, writable([]));
        }
        store = map.get(identifier);
        return map
    })
    return store
};

const updateData = (identifier, newData) => {
    logger.log(loggerCtxName, "updateData", identifier, newData.length, newData);
    const store = getSensorDataStore(identifier);
    store.update(oldData => {
        if (oldData) {
            logger.log(loggerCtxName, "updateData oldData", identifier, oldData, newData.length);
            return [...oldData, ...newData]
        } else {
            logger.log(loggerCtxName, "updateData newData", identifier, oldData, newData.length);
            return newData;
        }
    })
};

const setData = async (identifier, newData) => {
    logger.log(loggerCtxName, "setData", identifier, newData);
    console.log('setData called, data before set', newData);
    const store = getSensorDataStore(identifier);
    store.set(newData);
    logger.log(loggerCtxName, "setData newData", identifier, newData.length);
    await tick();
};

const transformStorageEventData = (data) => {
    let transformedData = [];

    if (data && Array.isArray(data)) {
        // Verify data format.
        data.forEach((item) => {
            // Loop through each item in the array.
            if (
                typeof item === "object" &&
                item !== null &&
                item.timestamp &&
                item.payload
            ) {
                // Type checks
                transformedData.push({
                    timestamp: item.timestamp,
                    payload: item.payload,
                });
            } else {
                // Output error for any malformed data
                console.warn(
                    "malformed data detected, skipping item",
                    item,
                );
            }
        });

        return transformedData;
    } else {
        console.warn("Invalid data format or data is missing:", data);
    }
};

const processStorageWorkerEvent = async (identifier, e) => {
    logger.log(loggerCtxName, "handleStorageWorkerEvent", e);
    const newData = transformStorageEventData(e.detail.data.result);

    let eventType = e.detail.type;

    switch (eventType) {
        case "clear-data-result":
            break;

        case "get-data-result":
            await setData(identifier, newData)
            break;
    }
};

const processAccumulatorEvent = (identifier, e) => {
    logger.log(loggerCtxName, "handleAccumulatorEvent", e);

    const sensorId = e?.detail?.data?.sensor_id;
    if (e?.detail?.data?.timestamp && e?.detail?.data?.payload && sensorId) {
        updateData(sensorId, [e.detail.data])
    } else {
        logger.log(loggerCtxName, "processAccumulatorEvent: payload is missing");
    }
};

const processSeedDataEvent = async (identifier, e) => {
    logger.log(loggerCtxName, "handleSeedDataEvent");
    if (Array.isArray(e?.detail?.data) && e?.detail?.data?.length > 0) {
        await setData(identifier, e.detail.data)
    } else {
        await setData(identifier, [])
    }
};

const handleAccumulatorEvent = (identifier, e) => {
    processAccumulatorEvent(identifier, e);
};

const handleStorageWorkerEvent = (identifier, e) => {
    processStorageWorkerEvent(identifier, e)
}

const handleSeedDataEvent = (identifier, e) => {
    processSeedDataEvent(identifier, e)
}


export {
    getSensorDataStore,
    handleStorageWorkerEvent,
    handleAccumulatorEvent,
    handleSeedDataEvent
};