// worker.js
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

const appendReadData = (sensorId, payload, maxLength) => { // Combines append and get
    return new Promise(async (resolve, reject) => {
        const tx = db.transaction(objectStoreName, 'readwrite');
        const store = tx.objectStore(objectStoreName);

        try {
            let existingData = await store.get(sensorId).result;
            let dataPoints = existingData ? existingData.dataPoints || [] : [];
            dataPoints.push({ timestamp: Date.now(), payload });


            if (maxLength && dataPoints.length > maxLength) {
                dataPoints = dataPoints.slice(-maxLength);
            }

            await store.put({ id: sensorId, dataPoints }); // Wait for put before resolving

            resolve(dataPoints); // Return the updated array

        } catch (error) {
            reject(error);
        }
    });
};


async function appendData(sensorId, payload, maxLength) {
    if (!db) {
        await openDatabase();
    }
    if (debug) console.log("appendData called for:", sensorId, "with payload:", payload, "and max length:", maxLength)
    return new Promise(async (resolve, reject) => {
        const tx = db.transaction(objectStoreName, 'readwrite');
        const store = tx.objectStore(objectStoreName);
        const request = store.get(sensorId)

        request.onerror = () => {
            console.error("Error in appendData get request:", request.error)
            reject(request.error);
        }
        request.onsuccess = async (event) => {
            let existingData = event.target.result;
            let dataPoints = [];
            const timestamp = Date.now();
            const newDataPoint = { timestamp: timestamp, payload: payload }
            if (debug) console.log("Existing data retrieved from IDB", existingData);

            if (existingData) {
                dataPoints = existingData.dataPoints || [];
            }

            dataPoints.push(newDataPoint);

            if (dataPoints.length > maxLength) {
                dataPoints = dataPoints.slice(-maxLength);
                if (debug) console.log("Data truncated, new data length:", dataPoints.length)
            }

            const putRequest = store.put({ id: sensorId, dataPoints: dataPoints });
            putRequest.onsuccess = () => {
                if (debug) console.log("Data updated on indexdb, new data length:", dataPoints.length)
                resolve(dataPoints)
            }
            putRequest.onerror = () => {
                console.error("Error in appendData put request:", putRequest.error)
                reject(putRequest.error)
            };
        }
    })
}

async function getData(sensorId) {
    if (!db) {
        await openDatabase();
    }
    if (debug) console.log("getData called for id:", sensorId)
    return new Promise(async (resolve, reject) => {
        const tx = db.transaction(objectStoreName, 'readonly');
        const store = tx.objectStore(objectStoreName);
        const request = store.get(sensorId)
        request.onerror = () => {
            console.error("Error in getData request:", request.error)
            reject(request.error);
        }
        request.onsuccess = (event) => {
            const existingData = event.target.result
            if (debug) console.log("Data retrieved from IDB, id:", sensorId, ", data:", existingData)
            resolve(existingData ? existingData.dataPoints : [])
        }
    })
}


self.addEventListener('message', async function (event) {
    const { type, data } = event.data;
    if (debug) console.log("Received message:", type, data)

    if (type === 'appendread-data') {
        const { id, payload, maxLength } = data;
        try {
            const result = await appendData(id, payload, maxLength);
            self.postMessage({ type: 'appendread-result', data: { id, result } });
            if (debug) console.log("appendread-result sent to the main thread", { id, result })
        } catch (error) {
            self.postMessage({ type: 'appendread-error', data: { id, error } });
            console.error("Error during appendReadData processing:", error)
        }
    } else if (type === 'append-data') {
        const { id, payload, maxLength } = data;
        try {
            const result = await appendData(id, payload, maxLength);
            self.postMessage({ type: 'append-result', data: { id, result } });
            if (debug) console.log("append-result sent to the main thread", { id, result })
        } catch (error) {
            self.postMessage({ type: 'append-error', data: { id, error } });
            console.error("Error during appendData processing:", error)
        }
    } else if (type === 'get-data') {
        const { id } = data
        try {
            const result = await getData(id)
            self.postMessage({ type: 'get-result', data: { id, result } });
            if (debug) console.log("get-result sent to the main thread", { id, result })
        } catch (error) {
            self.postMessage({ type: 'get-error', data: { id, error } });
            console.error("Error during getData processing:", error)
        }
    }
});