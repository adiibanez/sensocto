// indexeddb.js
let db;
const objectStoreName = 'sensorData';
const dbName = 'sensorDataDB';
const version = 1;
let debug = false;

//import { logger } from "./logger.js";
const loggerCtxName = "IndexedDB";

export function setDebug(value) {
    debug = value;
}

export function openDatabase() {

    return new Promise((resolve, reject) => {
        const request = indexedDB.open(dbName, version);

        if (debug) console.log("STORAGE Opening IndexedDB:", dbName, version, loggerCtxName);

        request.onerror = () => {
            if (debug) console.log(loggerCtxName, "Error opening IndexedDB:", request.error);
            reject(request.error);
        };

        request.onupgradeneeded = (event) => {
            const db = event.target.result;
            if (!db.objectStoreNames.contains(objectStoreName)) {
                const objectStore = db.createObjectStore(objectStoreName, { keyPath: 'id' });
                objectStore.createIndex('timestamps', 'timestamps', { multiEntry: true });
                if (debug) console.log(loggerCtxName, "STORAGE Object store created", objectStoreName);
            }
        };

        request.onsuccess = () => {
            db = request.result;
            if (debug) console.log(loggerCtxName, "STORAGE IndexedDB opened successfully");
            resolve(db);
        };
    });
}

export const handleClearData = async (sensor_id, attribute_id) => {
    const identifier = `${sensor_id}_${attribute_id}`;
    if (!db) {
        await openDatabase();
    }
    return new Promise(async (resolve, reject) => {
        const tx = db.transaction(objectStoreName, 'readwrite');
        const store = tx.objectStore(objectStoreName);

        try {
            const deleteRequest = store.delete(identifier);
            deleteRequest.onsuccess = () => resolve([]); // Resolve with empty data.
            deleteRequest.onerror = event => reject(event.target.error);
        } catch (e) {
            reject(e);
        }
    });
};

export const handleAppendData = async (sensor_id, attribute_id, payload, maxLength = 5000) => {
    const identifier = `${sensor_id}_${attribute_id}`;
    if (!db) await openDatabase();
    if (debug) console.log(loggerCtxName, "STORAGE appendData called for:", identifier, "with payload:", payload, "and max length:", maxLength);

    return new Promise(async (resolve, reject) => {
        const tx = db.transaction(objectStoreName, 'readwrite');
        const store = tx.objectStore(objectStoreName);

        try {
            let existingData = await new Promise((resolve, reject) => {
                const getRequest = store.get(identifier);
                getRequest.onerror = () => reject(getRequest.error);
                getRequest.onsuccess = () => resolve(getRequest.result);
            });

            let dataPoints = existingData ? existingData.dataPoints || [] : [];

            if (Array.isArray(payload)) {
                payload.forEach((item) => {
                    if (item.payload && item.timestamp) {
                        const newDataPoint = { timestamp: item.timestamp, payload: item };
                        dataPoints.push(newDataPoint);
                    }
                });
            } else {
                if (payload.payload && payload.timestamp) {
                    const newDataPoint = { timestamp: payload.timestamp, payload: payload };
                    dataPoints.push(newDataPoint);
                }
            }

            if (maxLength && dataPoints.length > maxLength) {
                dataPoints = dataPoints.slice(-maxLength); // Use slice to remove old points
            }

            // Sort dataPoints by timestamp
            dataPoints.sort((a, b) => a.timestamp - b.timestamp);

            const putRequest = store.put({ id: identifier, dataPoints });

            putRequest.onsuccess = () => {
                if (debug) console.log(loggerCtxName, "STORAGE Data updated on indexdb, new data length:", dataPoints.length);
                resolve(dataPoints.length); // resolve with the new count of data points
            };
            putRequest.onerror = (event) => reject(event.target.error);

        } catch (error) {
            if (debug) console.log(loggerCtxName, "Error during appendData processing:", error);
            reject(error);
        }

    });
};

export const handleAppendAndReadData = async (sensor_id, attribute_id, payload, maxLength = 100000) => {
    const identifier = `${sensor_id}_${attribute_id}`;
    if (!db) {
        await openDatabase();
    }
    logger.log(loggerCtxName, "STORAGE handleAppendAndReadData called for:", identifier, "with payload:", payload, "and max length:", maxLength);

    return new Promise(async (resolve, reject) => {
        const tx = db.transaction(objectStoreName, 'readwrite');
        const store = tx.objectStore(objectStoreName);

        try {
            let existingData = await new Promise((resolve, reject) => {
                const getRequest = store.get(identifier);
                getRequest.onerror = () => reject(getRequest.error);
                getRequest.onsuccess = () => resolve(getRequest.result);
            });

            let dataPoints = existingData ? existingData.dataPoints || [] : [];
            logger.log(loggerCtxName, "STORAGE existing data points length:", dataPoints.length);

            if (Array.isArray(payload.data)) {
                payload.data.forEach((item) => {
                    if (item.payload && item.timestamp) {
                        const newDataPoint = { timestamp: item.timestamp, payload: item };
                        dataPoints.push(newDataPoint);
                    }
                });
            } else {
                if (payload.payload && payload.timestamp) {
                    const newDataPoint = { timestamp: payload.timestamp, payload: payload };
                    dataPoints.push(newDataPoint);
                }
            }

            if (maxLength && dataPoints.length > maxLength) {
                dataPoints = dataPoints.slice(-maxLength);
            }

            dataPoints.sort((a, b) => a.timestamp - b.timestamp);

            logger.log(loggerCtxName, "STORAGE new data points length before put:", dataPoints.length);

            const putRequest = store.put({ id: identifier, dataPoints });
            putRequest.onsuccess = () => {
                logger.log(loggerCtxName, "STORAGE Data updated on indexdb, new data length:", dataPoints.length);
                resolve(dataPoints);
            };
            putRequest.onerror = (event) => {
                logger.log(loggerCtxName, "STORAGE Error in handleAppendAndReadData put request:", putRequest.error);
                reject(putRequest.error);
            };
        } catch (error) {
            logger.log(loggerCtxName, "STORAGE Error during handleAppendAndReadData processing:", error);
            reject(error);
        }
    });
};

export const handleSeedData = async (sensor_id, attribute_id, seedData, reset = true) => {
    const identifier = `${sensor_id}_${attribute_id}`;
    if (!db) {
        await openDatabase();
    }
    return new Promise(async (resolve, reject) => {
        const tx = db.transaction(objectStoreName, 'readwrite');
        const store = tx.objectStore(objectStoreName);

        try {
            if (debug) console.log(loggerCtxName, "STORAGE", "seedData", identifier, seedData.length);
            const putRequest = store.put({ id: identifier, dataPoints: seedData });
            putRequest.onsuccess = () => resolve(seedData);
            putRequest.onerror = event => reject(event.target.error);
        } catch (err) {
            reject(err);
        }
    });

};

export const handleGetLastTimestamp = async (sensor_id, attribute_id) => {
    const identifier = `${sensor_id}_${attribute_id}`;
    if (!db) {
        await openDatabase();
    }
    return new Promise(async (resolve, reject) => {
        const tx = db.transaction(objectStoreName, 'readonly');
        const store = tx.objectStore(objectStoreName);
        const request = store.get(identifier);
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
export const handleGetAllLatestTimestamps = async () => {
    if (!db) {
        await openDatabase();
    }
    return new Promise((resolve, reject) => {
        const tx = db.transaction(objectStoreName, 'readonly');
        const store = tx.objectStore(objectStoreName);
        const request = store.getAll();

        request.onerror = () => reject(request.error);
        request.onsuccess = (event) => {
            const allData = event.target.result;
            const latestTimestamps = allData.map(item => {
                if (item.dataPoints && item.dataPoints.length > 0) {

                    let latestTimestamp = item.dataPoints.slice(-1)[0].timestamp;

                    console.log("handleGetAllLatestTimestamps", item.id, item.dataPoints.length, latestTimestamp);
                    return { id: item.id, timestamp: latestTimestamp };
                }
                return { id: item.id, timestamp: null };
            });
            resolve(latestTimestamps);
        };
    });
};
