// storage-worker.js
import {
    openDatabase,
    handleClearData,
    handleAppendData,
    handleAppendAndReadData,
    handleSeedData,
    handleGetLastTimestamp,
    setDebug
} from './indexeddb.js';

//import { logger } from "./logger.js";

const loggerCtxName = "WebWorker.IndexedDB";

setDebug(false);

self.addEventListener('message', async function (event) {
    const { type, data } = event.data;
    try {
        let result;
        if (type === 'append-read-data') {
            result = await handleAppendAndReadData(data.sensor_id, data.attribute_id, data.payload, data.maxLength);
            self.postMessage({ type: 'append-read-data-result', data: { sensor_id: data.sensor_id, attribute_id: data.attribute_id, result, queue: getQueueStatus() } });
        } else if (type === 'append-data') {
            result = await handleAppendData(data.sensor_id, data.attribute_id, data.payload, data.maxLength);
            self.postMessage({ type: 'append-data-result', data: { sensor_id: data.sensor_id, attribute_id: data.attribute_id, result, queue: getQueueStatus() } });
        } else if (type === 'overwrite-data') {
            // result = await handleOverwriteData(data.sensor_id, data.attribute_id, data.payload);
            // self.postMessage({ type: 'overwrite-data-result', data: { sensor_id: data.sensor_id, attribute_id: data.attribute_id, result, queue: getQueueStatus() } });
        } else if (type === 'housekeep') {
            // result = await handleHousekeep(data.sensor_id, data.attribute_id, data.staleDataHours);
            // self.postMessage({ type: 'housekeep-result', data: { sensor_id: data.sensor_id, attribute_id: data.attribute_id, result, queue: getQueueStatus() } });
        } else if (type === 'clear-data') {
            result = await handleClearData(data.sensor_id, data.attribute_id);
            self.postMessage({ type: 'clear-data-result', data: { sensor_id: data.sensor_id, attribute_id: data.attribute_id, result, queue: getQueueStatus() } });
        } else if (type === 'seed-data') {
            result = await handleSeedData(data.sensor_id, data.attribute_id, data.seedData);
            self.postMessage({ type: 'seed-data-result', data: { sensor_id: data.sensor_id, attribute_id: data.attribute_id, result: result, queue: getQueueStatus() } });
        } else if (type === 'get-last-timestamp') {
            result = await handleGetLastTimestamp(data.sensor_id, data.attribute_id);
            self.postMessage({ type: 'get-last-timestamp-result', data: { sensor_id: data.sensor_id, attribute_id: data.attribute_id, result, queue: getQueueStatus() } });
        } else {
            self.postMessage({ type: `${type}-error`, data: { sensor_id: data.sensor_id, attribute_id: data.attribute_id, error: "Message type does not exist " + type, queue: getQueueStatus() } });
        }
    } catch (error) {
        self.postMessage({ type: `${type}-error`, data: { sensor_id: data.sensor_id, attribute_id: data.attribute_id, error: error.message || error, queue: getQueueStatus() } });
        console.log(loggerCtxName, `Error during ${type} operation:`, error);
    }
});

const getQueueStatus = () => {
    return {
        size: 0
    };
};