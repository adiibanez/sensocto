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
    if (!db) {
        await openDatabase();
    }
    return new Promise(async (resolve, reject) => {
        const tx = db.transaction(objectStoreName, 'readwrite');
        const store = tx.objectStore(objectStoreName);

        try {
            const deleteRequest = store.delete(sensorId);
            deleteRequest.onsuccess = () => {
                enqueueUpdate(sensorId, []);
                scheduleDebouncedUpdate();
                resolve([]); // Correctly resolve the promise
            }
            deleteRequest.onerror = (event) => reject(event.target.error);
        } catch (error) {
            console.error("Error clearing data:", error);
            reject(error); // Also reject if there is an error in try block.
        }
    });
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
            const timestamp = payload.timestamp;
            const newDataPoint = { timestamp, payload };
            dataPoints.push(newDataPoint);

            if (maxLength && dataPoints.length > maxLength) {
                dataPoints = dataPoints.slice(-maxLength);
            }

            const putRequest = store.put({ id: sensorId, dataPoints });
            putRequest.onsuccess = () => {
                if (debug) console.log("Data updated on indexdb, new data length:", dataPoints.length)
                resolve(newDataPoint);
            };
            putRequest.onerror = (event) => {
                console.error("Error in appendData put request:", putRequest.error)
                reject(putRequest.error);
            };

            enqueueUpdate(sensorId, dataPoints); // update queue.
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
            const timestamp = payload.timestamp;
            const newDataPoint = { timestamp: payload.timestamp, payload: payload } // include timestamp
            dataPoints.push(newDataPoint);


            if (maxLength && dataPoints.length > maxLength) {
                dataPoints = dataPoints.slice(-maxLength);
            }

            const putRequest = store.put({ id: sensorId, dataPoints });

            putRequest.onsuccess = () => {
                if (debug) console.log("Data updated on indexdb, new data length:", dataPoints.length)
                resolve(dataPoints);
            };
            putRequest.onerror = (event) => {
                console.error("Error in handleAppendAndReadData put request:", putRequest.error)
                reject(putRequest.error);
            };

            enqueueUpdate(sensorId, dataPoints);
            scheduleDebouncedUpdate();
        } catch (error) {
            console.error("Error in handleAppendAndReadData: ", error);
            reject(error);
        }

    });
};



const handleSeedData = async (sensorId, seedData) => {
    if (!db) {
        await openDatabase();
    }
    return new Promise(async (resolve, reject) => {
        const tx = db.transaction(objectStoreName, 'readwrite');
        const store = tx.objectStore(objectStoreName);

        try {
            const putRequest = store.put({ id: sensorId, dataPoints: seedData }); // Seed data.
            putRequest.onsuccess = () => {
                resolve();
                enqueueUpdate(sensorId, seedData); // Send to queue.
                scheduleDebouncedUpdate();
            };

            putRequest.onerror = (event) => {
                console.error("Error in handleSeedData put request:", putRequest.error)
                reject(putRequest.error);
            };
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
            if (existingData && existingData.dataPoints && existingData.dataPoints.length > 0) { // If there is data.
                const lastTimestamp = existingData.dataPoints.slice(-1)[0].timestamp; // Get timestamp.
                resolve(lastTimestamp);
            } else {
                resolve(null) // Resolve with null if no data present.
            }

        };
    })
};



const enqueueUpdate = (sensorId, data) => {
    if (!updateQueue[sensorId]) {
        updateQueue[sensorId] = [];
    }
    updateQueue[sensorId] = data; // Use latest data.
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
    if (queueProcessing) return;
    queueProcessing = true;

    try {
        for (const sensorId in updateQueue) {
            const queueStatus = getQueueStatus();
            const data = updateQueue[sensorId];

            if (Array.isArray(data) && data.length > 0 && data[0].timestamp) {
                self.postMessage({ type: 'updated-read-data', data: { id: sensorId, result: data, queue: queueStatus } }); // send queue info on the read action
            } else if (data && Object.keys(data).length > 0 && data.timestamp) {
                self.postMessage({ type: 'updated-data', data: { id: sensorId, result: data, queue: queueStatus } });  // send queue info on the simple append.
            } else if (Array.isArray(data) && data.length === 0) { // Handle empty data cases, for `clear-data`.
                self.postMessage({ type: 'updated-clear-data', data: { id: sensorId, result: data, queue: getQueueStatus() } });
            }
            else {
                console.warn("ProcessQueue: Could not determine type of data. Skipping update:", data);
            }
        }
        updateQueue = {};

    } finally {
        queueProcessing = false;
        if (Object.keys(updateQueue).length > 0) {
            processQueue(); // Reprocess immediately if queue isn't empty.
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
            self.postMessage({ type: 'append-read-data-result', data: { id: data.id, result, queue: getQueueStatus() } });
        }
        else if (type === 'append-data') {
            if (debug) console.log('WORKER append-data', data);
            result = await handleAppendData(data.id, data.payload, data.maxLength);
            self.postMessage({ type: 'append-data-result', data: { id: data.id, result, queue: getQueueStatus() } }); // Send also queue info.
        } else if (type === 'clear-data') { // Handle explicit housekeeping request
            result = await handleClearData(data.id);
            self.postMessage({ type: 'clear-data-result', data: { id: data.id, result, queue: getQueueStatus() } });// Send also queue info.
        } else if (type === 'seed-data') { // Handle explicit seed request
            if (debug) console.log("WORKER seed-data", data);
            result = await handleSeedData(data.id, data.seedData);
            self.postMessage({ type: 'seed-data-result', data: { id: data.id, queue: getQueueStatus() } });// Send also queue info.
        } else if (type === 'get-last-timestamp') { // timestamp request
            result = await handleGetLastTimestamp(data.id);
            self.postMessage({ type: 'get-last-timestamp-result', data: { id: data.id, result, queue: getQueueStatus() } });// Send also queue info.
        }
        else {
            self.postMessage({ type: `${type}-error`, data: { id: data.id, error: "Message type does not exists " + type, queue: getQueueStatus() } });
        }
    } catch (error) {
        self.postMessage({ type: `${type}-error`, data: { id: data.id, error: error.message || error, queue: getQueueStatus() } }); // Send error msg with queue info.
        console.error(`Error during ${type} operation:`, error);
    }
});