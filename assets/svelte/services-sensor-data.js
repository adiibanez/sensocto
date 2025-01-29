// sensorDataService.js
import { get, writable } from 'svelte/store';
import { logger } from "./logger.js";

let loggerCtxName = "SensorDataService";

function createSensorDataService() {
    const sensorDataMap = writable(new Map()); // Store data per sensor
    //const sensorDataMap = writable() // Store data per sensor

    logger.log(loggerCtxName, "createSensorDataService");

    const getSensorDataStore = (identifier) => {
        logger.log(loggerCtxName, "getSensorDataStore {identifier}");
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
        logger.log(loggerCtxName, "updateData", identifier, newData.length);
        const store = getSensorDataStore(identifier);
        store.update(oldData => {
            if (oldData) {
                return [...oldData, ...newData]
            } else {
                return newData;
            }
        })
    };

    const setData = (identifier, newData) => {
        logger.log(loggerCtxName, "setData", identifier, newData);
        const store = getSensorDataStore(identifier);
        store.set(newData);
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
                        payload: item.payload.payload,
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


    const processStorageWorkerEvent = (identifier, e) => {
        logger.log(loggerCtxName, "handleStorageWorkerEvent", identifier, e);
        const newData = transformStorageEventData(e.detail.data.result);

        let eventType = e.detail.type;

        switch (eventType) {
            case "clear-data-result":
                break;

            case "get-data-result":
                setData(identifier, newData)
                break;
        }
    };

    const processAccumulatorEvent = (identifier, e) => {
        logger.log(loggerCtxName, "handleAccumulatorEvent", identifier, e);

        if (e?.detail?.data?.timestamp && e?.detail?.data?.payload) {
            updateData(identifier, [e.detail.data])
        }
    };

    const processSeedDataEvent = (identifier, e) => {
        logger.log(loggerCtxName, "handleSeedDataEvent", identifier);
        if (Array.isArray(e?.detail?.data) && e?.detail?.data?.length > 0) {
            setData(identifier, e.detail.data)
        } else {
            setData(identifier, [])
        }
    };

    return {
        getSensorDataStore,
        processStorageWorkerEvent,
        processAccumulatorEvent,
        processSeedDataEvent
    };
}

export const sensorDataService = createSensorDataService();