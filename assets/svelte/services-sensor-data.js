// sensorDataService.js
import { get, writable } from 'svelte/store';
import { logger } from "./logger.js";

let loggerCtxName = "SensorDataService";

function createSensorDataService(componentId) {
    const sensorDataMap = writable(new Map()); // Store data per sensor
    //const sensorDataMap = writable() // Store data per sensor

    let identifier;

    logger.log(loggerCtxName, "createSensorDataService", componentId);

    const getSensorDataStore = (identifier) => {
        logger.log(loggerCtxName, "getSensorDataStore", identifier, componentId);

        identifier = identifier
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
        logger.log(loggerCtxName, "updateData", identifier, newData.length, componentId);
        const store = getSensorDataStore(identifier);
        store.update(oldData => {
            if (oldData) {
                logger.log(loggerCtxName, "updateData oldData", identifier, oldData, newData.length, componentId);
                return [...oldData, ...newData]
            } else {
                logger.log(loggerCtxName, "updateData newData", identifier, oldData, newData.length, componentId);
                return newData;
            }
        })
    };

    const setData = (identifier, newData) => {
        logger.log(loggerCtxName, "setData", identifier, newData, componentId);
        const store = getSensorDataStore(identifier);
        store.set(newData);
        logger.log(loggerCtxName, "setData newData", identifier, newData.length, componentId);
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


    const processStorageWorkerEvent = (e) => {
        logger.log(loggerCtxName, "handleStorageWorkerEvent", identifier, e, componentId);
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

    const processAccumulatorEvent = (e) => {
        logger.log(loggerCtxName, "handleAccumulatorEvent", e, componentId);

        const sensorId = e?.detail?.data?.sensor_id;

        if (e?.detail?.data?.timestamp && e?.detail?.data?.payload && sensorId) {
            updateData(sensorId, [e.detail.data])
        }
    };


    const processSeedDataEvent = (e) => {
        logger.log(loggerCtxName, "handleSeedDataEvent", identifier, componentId);
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

export const createSensorDataServiceInstance = (componentId) => createSensorDataService(componentId)