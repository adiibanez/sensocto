// sensorDataService.js
import { get } from 'svelte/store';
import { logger } from "./logger.js";
import { tick } from 'svelte';

let loggerCtxName = "SensorDataService";

const updateData = (store, identifier, newData) => {
    //logger.log(loggerCtxName, "updateData", identifier, newData.length, newData);
    store.update(oldData => {
        if (oldData) {
            //logger.log(loggerCtxName, "updateData oldData", identifier, oldData, newData.length);
            return [...oldData, ...newData]
        } else {
            // logger.log(loggerCtxName, "updateData newData", identifier, oldData, newData.length);
            return newData;
        }
    })
};

const setData = async (store, identifier, newData) => {
    //logger.log(loggerCtxName, "setData", identifier, newData);
    //console.log('setData called, data before set', newData);
    store.set(newData);
    //logger.log(loggerCtxName, "setData newData", identifier, newData.length);
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

const processStorageWorkerEvent = async (store, identifier, e) => {
    // logger.log(loggerCtxName, "handleStorageWorkerEvent", e);
    const newData = transformStorageEventData(e.detail.data.result);

    let eventType = e.detail.type;

    switch (eventType) {
        case "clear-data-result":
            break;

        case "get-data-result":
            await setData(store, identifier, newData)
            break;
    }
};

const processAccumulatorEvent = (store, identifier, e) => {
    // logger.log(loggerCtxName, "handleAccumulatorEvent", e);

    const sensorId = e?.detail?.data?.sensor_id;
    if (e?.detail?.data?.timestamp && e?.detail?.data?.payload && sensorId) {
        updateData(store, sensorId, [e.detail.data])
    } else {
        logger.log(loggerCtxName, "processAccumulatorEvent: payload is missing");
    }
};

const processSeedDataEvent = async (store, identifier, e) => {
    // logger.log(loggerCtxName, "handleSeedDataEvent");
    if (Array.isArray(e?.detail?.data) && e?.detail?.data?.length > 0) {
        await setData(store, identifier, e.detail.data)
    } else {
        await setData(store, identifier, [])
    }
};

export {
    processStorageWorkerEvent,
    processAccumulatorEvent,
    processSeedDataEvent
};