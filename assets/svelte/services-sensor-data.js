// sensorDataService.js
import { get } from 'svelte/store';
import { logger } from "./logger_svelte.js";
import { tick } from 'svelte';

let loggerCtxName = "SensorDataService";

const updateData = (store, sensor_id, attribute_id, newData) => {
    logger.log(loggerCtxName, "updateData", sensor_id, attribute_id, newData.length, newData);
    store.update(oldData => {
        if (oldData) {
            //logger.log(loggerCtxName, "updateData oldData", identifier, oldData, newData.length);
            return [...oldData, ...newData].slice(-100000);
        } else {
            // logger.log(loggerCtxName, "updateData newData", identifier, oldData, newData.length);
            return newData;
        }
    })
};

const setData = async (store, sensor_id, attribute_id, newData) => {
    logger.log(loggerCtxName, "setData", sensor_id, attribute_id, newData.length, newData);
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

            if (typeof item.payload === "object" && item?.payload?.timestamp !== null && item?.payload?.payload !== null) {
                let newItem = {
                    timestamp: item.timestamp,
                    payload: item.payload.payload,
                }
                // console.log('item', newItem, item);
                transformedData.push(newItem);
            } else if (
                typeof item === "object" &&
                item !== null &&
                item?.timestamp !== null &&
                item?.payload !== null
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

const processStorageWorkerEvent = async (store, sensor_id, attribute_id, e) => {
    logger.log(loggerCtxName, "handleStorageWorkerEvent", sensor_id, attribute_id, e);

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

const processAccumulatorEvent = (store, sensor_id, attribute_id, e) => {
    logger.log(loggerCtxName, "handleAccumulatorEvent", e, sensor_id, attribute_id, Array.isArray(e?.detail?.data));

    // const sensorId = e?.detail?.data?.sensor_id;

    // batch update
    if (Array.isArray(e?.detail?.data)) {
        updateData(store, sensor_id, attribute_id, e.detail.data);
        // single value update
    } else if (e?.detail?.data?.timestamp && e?.detail?.data?.payload) {
        updateData(store, sensor_id, attribute_id, [e.detail.data])
    } else {
        logger.log(loggerCtxName, "processAccumulatorEvent: payload is missing", sensor_id, attribute_id);
    }
};

const processSeedDataEvent = async (store, sensor_id, attribute_id, e) => {
    logger.log(loggerCtxName, "handleSeedDataEvent", e);
    const transformedData = transformStorageEventData(e.detail.data)
    // let newData = e.detail.data;
    if (Array.isArray(transformedData)) {
        await setData(store, sensor_id, attribute_id, transformedData);
    } else {
        await setData(store, sensor_id, attribute_id, [])
    }
};

export {
    processStorageWorkerEvent,
    processAccumulatorEvent,
    processSeedDataEvent
};