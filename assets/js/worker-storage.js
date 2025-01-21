// storage-worker.js
let db;
const objectStoreName = 'sensorData';
const dbName = 'sensorDataDB';
const version = 1;
let debug = false;


let updateQueue = {};
let queueProcessing = false;

// Dynamic configuration
let BATCH_SIZE = 1;
let DEBOUNCE_TIME = 250;
const MAX_BATCH_SIZE = 50;
const MIN_DEBOUNCE_TIME = 0;
const MAX_DEBOUNCE_TIME = 500;

let debounceTimeout;

function openDatabase() {
    return new Promise((resolve, reject) => {
        const request = indexedDB.open(dbName, version);

        request.onerror = () => {
            console.error("Error opening IndexedDB:", request.error);
            reject(request.error);
        };

        request.onupgradeneeded = (event) => {
            const db = event.target.result;
            if (!db.objectStoreNames.contains(objectStoreName)) {
                const objectStore = db.createObjectStore(objectStoreName, { keyPath: 'id' });
                objectStore.createIndex('timestamps', 'timestamps', { multiEntry: true })
                console.log("Object store created", objectStoreName)
            }
        };
        request.onsuccess = () => {
            db = request.result;
            console.log("IndexedDB opened successfully");
            resolve(db);
        };
    });
}

const getQueueStatus = () => {
    return {
        size: Object.keys(updateQueue).length
    };
};

const handleClearData = async (sensorId) => {
    try {
        if (!db) await openDatabase();
        const tx = db.transaction(objectStoreName, 'readwrite');
        const store = tx.objectStore(objectStoreName);
        await new Promise((resolve, reject) => {
            const deleteRequest = store.delete(sensorId);
            deleteRequest.onsuccess = resolve;
            deleteRequest.onerror = reject;
        });

        enqueueUpdate(sensorId, []); // Update queue with empty data
        scheduleDebouncedUpdate();
        resolve([]); // resolve with an empty array to signal success

    } catch (error) {
        console.error("Error clearing data:", error);
        throw error;
    }
};


const handleAppendData = async (sensorId, payload, maxLength) => {
    if (!db) {
        await openDatabase();
    }
    if (debug) console.log("appendData called for:", sensorId, "with payload:", payload, "and max length:", maxLength)

    return new Promise(async (resolve, reject) => {
        const tx = db.transaction(objectStoreName, 'readwrite');
        const store = tx.objectStore(objectStoreName);
        try {
            let existingData = await new Promise((resolve, reject) => {
                const getRequest = store.get(sensorId);
                getRequest.onerror = () => reject(getRequest.error);
                getRequest.onsuccess = () => resolve(getRequest.result);
            });


            let dataPoints = existingData ? existingData.dataPoints || [] : [];
            const timestamp = Date.now();
            const newDataPoint = { timestamp, payload };
            dataPoints.push(newDataPoint); // Append new data.

            if (maxLength && dataPoints.length > maxLength) {
                dataPoints = dataPoints.slice(-maxLength); // Truncate if necessary
            }


            const putRequest = store.put({ id: sensorId, dataPoints });
            putRequest.onsuccess = () => {
                if (debug) console.log("Data updated on indexdb, new data length:", dataPoints.length)
                resolve(newDataPoint); //  resolve with single datapoint.
            };
            putRequest.onerror = (event) => {
                console.error("Error in appendData put request:", putRequest.error)
                reject(putRequest.error)
            };

            enqueueUpdate(sensorId, dataPoints); // Add to queue.
            scheduleDebouncedUpdate();
        } catch (error) {
            console.error("Error in appendData: ", error);
            reject(error);
        }
    })
};

const handleAppendAndReadData = async (sensorId, payload, maxLength) => {
    if (!db) {
        await openDatabase();
    }
    if (debug) console.log("handleAppendAndReadData called for:", sensorId, "with payload:", payload, "and max length:", maxLength)

    return new Promise(async (resolve, reject) => {
        const tx = db.transaction(objectStoreName, 'readwrite');
        const store = tx.objectStore(objectStoreName);
        try {

            let existingData = await new Promise((resolve, reject) => {
                const getRequest = store.get(sensorId);
                getRequest.onerror = () => reject(getRequest.error);
                getRequest.onsuccess = () => resolve(getRequest.result);
            });

            let dataPoints = existingData ? existingData.dataPoints || [] : [];
            const timestamp = Date.now();
            const newDataPoint = { timestamp: timestamp, payload: payload } // new payload.
            dataPoints.push(newDataPoint);


            if (maxLength && dataPoints.length > maxLength) {
                dataPoints = dataPoints.slice(-maxLength);
            }

            const putRequest = store.put({ id: sensorId, dataPoints });

            putRequest.onsuccess = () => {
                if (debug) console.log("Data updated on indexdb, new data length:", dataPoints.length)
                resolve(dataPoints) // Send all data back
            };

            putRequest.onerror = (event) => {
                console.error("Error in handleAppendAndReadData put request:", putRequest.error)
                reject(putRequest.error);
            };

            enqueueUpdate(sensorId, dataPoints); // Update queue.
            scheduleDebouncedUpdate();

        } catch (error) {
            console.error("Error in handleAppendAndReadData: ", error);
            reject(error);
        }
    })
};


// New handler to seed data.

const handleSeedData = async (sensorId, seedData) => {
    if (!db) {
        await openDatabase();
    }

    return new Promise(async (resolve, reject) => {
        const tx = db.transaction(objectStoreName, 'readwrite');
        const store = tx.objectStore(objectStoreName);

        try {
            const putRequest = store.put({ id: sensorId, dataPoints: seedData }); // Overwrite data.
            putRequest.onsuccess = () => {
                resolve();
                enqueueUpdate(sensorId, seedData); // Send the new data to queue
                scheduleDebouncedUpdate();
            }
            putRequest.onerror = (event) => {
                console.error("Error in handleSeedData put request:", putRequest.error)
                reject(putRequest.error);
            }
        }
        catch (error) {
            console.error("Error in seed data: ", error);
            reject(error);
        }
    })
};


const handleGetLastTimestamp = async (sensorId) => {
    if (!db) {
        await openDatabase();
    }
    return new Promise(async (resolve, reject) => {
        const tx = db.transaction(objectStoreName, 'readonly');
        const store = tx.objectStore(objectStoreName);
        const request = store.get(sensorId)
        request.onerror = () => reject(request.error);
        request.onsuccess = (event) => {
            const existingData = event.target.result
            if (existingData && existingData.dataPoints && existingData.dataPoints.length > 0) { // check if data exists
                const lastTimestamp = existingData.dataPoints.slice(-1)[0].timestamp // Get last timestamp
                resolve(lastTimestamp)
            } else {
                resolve(null) // Resolve with null if no data.
            }

        };
    })
};



const enqueueUpdate = (sensorId, data) => {
    if (!updateQueue[sensorId]) {
        updateQueue[sensorId] = [];
    }
    updateQueue[sensorId] = data;  // Overwrite the last data.
};


const scheduleDebouncedUpdate = () => {
    clearTimeout(debounceTimeout);

    // Dynamic debounce and batch size adjustment (adjust logic as needed)
    const queueSize = Object.keys(updateQueue).length;
    if (queueSize > 20) {
        DEBOUNCE_TIME = Math.min(DEBOUNCE_TIME * 1.2, MAX_DEBOUNCE_TIME);
        BATCH_SIZE = Math.min(BATCH_SIZE * 1.5, MAX_BATCH_SIZE);
    } else if (queueSize < 5 && DEBOUNCE_TIME > MIN_DEBOUNCE_TIME) {
        DEBOUNCE_TIME = Math.max(MIN_DEBOUNCE_TIME, DEBOUNCE_TIME / 1.2);
        BATCH_SIZE = Math.max(10, BATCH_SIZE / 1.5);
    }

    debounceTimeout = setTimeout(processQueue, DEBOUNCE_TIME);
};


const processQueue = async () => {
    if (queueProcessing) return; // Handle double process
    queueProcessing = true;

    try {
        for (const sensorId in updateQueue) {
            self.postMessage({ type: 'updated-data', data: { id: sensorId, result: updateQueue[sensorId], queue: getQueueStatus() } }); // include queue
        }
        updateQueue = {};

    } finally {
        queueProcessing = false;
        if (Object.keys(updateQueue).length > 0) { // Reprocess, if the queue is not empty.
            processQueue();
        }
    }
};


self.addEventListener('message', async function (event) {
    const { type, data } = event.data;
    try {
        let result;
        if (type === 'append-read-data') {
            if (debug) console.log('WORKER append-read-data', data);
            result = await handleAppendAndReadData(data.id, data.payload, data.maxLength);
            self.postMessage({ type: 'append-read-data-result', data: { id: data.id, result, queue: getQueueStatus() } }); // Also send queue
        } else if (type === 'append-data') {
            if (debug) console.log('WORKER append-data', data);
            result = await handleAppendData(data.id, data.payload, data.maxLength);
            self.postMessage({ type: 'append-data-result', data: { id: data.id, result, queue: getQueueStatus() } }); // Send with queue.
        } else if (type === 'clear-data') { // Handle explicit housekeeping request
            result = await handleClearData(data.id);
            self.postMessage({ type: 'clear-data-result', data: { id: data.id, result, queue: getQueueStatus() } }); // Send with queue.
        } else if (type === 'seed-data') {  // new seed request
            if (debug) console.log("WORKER seed-data", data);
            result = await handleSeedData(data.id, data.seedData);
            self.postMessage({ type: 'seed-data-result', data: { id: data.id, queue: getQueueStatus() } });
        } else if (type === 'get-last-timestamp') {
            result = await handleGetLastTimestamp(data.id);
            self.postMessage({ type: 'get-last-timestamp-result', data: { id: data.id, result, queue: getQueueStatus() } });
        } else {
            self.postMessage({ type: `${type}-error`, data: { id: data.id, error: "Message type does not exists " + type, queue: getQueueStatus() } });
        }

    } catch (error) {
        self.postMessage({ type: `${type}-error`, data: { id: data.id, error: error.message || error, queue: getQueueStatus() } });
        console.error(`Error during ${type} operation:`, error);
    }
});