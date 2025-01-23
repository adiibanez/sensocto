// storage-worker.js
let db;
const objectStoreName = 'sensorData';
const dbName = 'sensorDataDB';
const version = 1;
let debug = false;

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
                console.log("STORAGE Object store created", objectStoreName)

            }
        };

        request.onsuccess = () => {
            db = request.result;
            console.log("STORAGE IndexedDB opened successfully");
            resolve(db);
        };
    });
}

const getQueueStatus = () => {
    return {
        size: 0
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
            deleteRequest.onsuccess = () => resolve([]); // Resolve with empty data.
            deleteRequest.onerror = event => reject(event.target.error);
        } catch (e) {
            reject(e)
        }
    });
};

const handleAppendData = async (sensorId, payload, maxLength) => {
    if (!db) await openDatabase();
    if (debug) console.log("STORAGE appendData called for:", sensorId, "with payload:", payload, "and max length:", maxLength);

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

            const newDataPoint = { timestamp: payload.timestamp, payload: payload };
            dataPoints.push(newDataPoint);

            // Sort the data by timestamp before saving:
            // TODO: check if housekeeping is required when under heavy load ( events out of order )
            //dataPoints.sort((a, b) => a.timestamp - b.timestamp);

            if (maxLength && dataPoints.length > maxLength) {
                dataPoints = dataPoints.slice(-maxLength); // Use slice to remove old points
            }


            const putRequest = store.put({ id: sensorId, dataPoints });

            putRequest.onsuccess = () => {
                if (debug) console.log("STORAGE Data updated on indexdb, new data length:", dataPoints.length)
                resolve(newDataPoint); // resolve with all points.
            };
            putRequest.onerror = (event) => reject(event.target.error);

        } catch (error) {
            console.error("Error during appendData processing:", error)
            reject(error);
        }

    });
};

const handleAppendAndReadData = async (sensorId, payload, maxLength) => {
    if (!db) {
        await openDatabase();
    }
    if (debug) console.log("STORAGE handleAppendAndReadData called for:", sensorId, "with payload:", payload, "and max length:", maxLength)

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
            const newDataPoint = { timestamp: payload.timestamp, payload: payload } // include timestamp
            dataPoints.push(newDataPoint);
            dataPoints.sort((a, b) => a.timestamp - b.timestamp);

            if (maxLength && dataPoints.length > maxLength) {
                dataPoints = dataPoints.slice(-maxLength);
            }

            const putRequest = store.put({ id: sensorId, dataPoints });
            putRequest.onsuccess = () => {
                if (debug) console.log("STORAGE Data updated on indexdb, new data length:", dataPoints.length)
                resolve(dataPoints);
            };
            putRequest.onerror = (event) => {
                console.error("STORAGE Error in handleAppendAndReadData put request:", putRequest.error)
                reject(putRequest.error);
            };
        } catch (error) {
            console.error("STORAGE Error during handleAppendAndReadData processing:", error)
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
            console.log("STORAGE", "seedData", sensorId, seedData.length);
            const putRequest = store.put({ id: sensorId, dataPoints: seedData });
            putRequest.onsuccess = () => resolve();
            putRequest.onerror = event => reject(event.target.error);
        } catch (err) {
            reject(err);
        }
    });

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
            const existingData = event.target.result;
            if (existingData && existingData.dataPoints && existingData.dataPoints.length > 0) {
                const lastTimestamp = existingData.dataPoints.slice(-1)[0].timestamp;
                resolve(lastTimestamp);
            } else {
                resolve(null);
            }
        };
    });
};

self.addEventListener('message', async function (event) {
    const { type, data } = event.data;
    try {
        let result;
        if (type === 'append-read-data') {
            result = await handleAppendAndReadData(data.id, data.payload, data.maxLength);
            self.postMessage({ type: 'append-read-data-result', data: { id: data.id, result, queue: getQueueStatus() } });
        } else if (type === 'append-data') {
            result = await handleAppendData(data.id, data.payload, data.maxLength);
            self.postMessage({ type: 'append-data-result', data: { id: data.id, result, queue: getQueueStatus() } }); // Send also queue info.
        } else if (type === 'overwrite-data') {
            // result = await handleOverwriteData(data.id, data.payload);
            // self.postMessage({ type: 'overwrite-data-result', data: { id: data.id, result, queue: getQueueStatus() } });
        }
        else if (type === 'housekeep') { // Handle explicit housekeeping request
            //   result = await handleHousekeep(data.id, data.staleDataHours);
            // self.postMessage({ type: 'housekeep-result', data: { id: data.id, result, queue: getQueueStatus() } });
        } else if (type === 'clear-data') {
            result = await handleClearData(data.id);
            self.postMessage({ type: 'clear-data-result', data: { id: data.id, result, queue: getQueueStatus() } });
        } else if (type === 'seed-data') {
            result = await handleSeedData(data.id, data.seedData);
            self.postMessage({ type: 'seed-data-result', data: { id: data.id, queue: getQueueStatus() } });
        }
        else if (type === 'get-last-timestamp') { // timestamp request
            result = await handleGetLastTimestamp(data.id);
            self.postMessage({ type: 'get-last-timestamp-result', data: { id: data.id, result, queue: getQueueStatus() } });// Send also queue info.
        } else {
            self.postMessage({ type: `${type}-error`, data: { id: data.id, error: "Message type does not exists " + type, queue: getQueueStatus() } });
        }
    } catch (error) {
        self.postMessage({ type: `${type}-error`, data: { id: data.id, error: error.message || error, queue: getQueueStatus() } });
        console.error(`Error during ${type} operation:`, error);
    }
});