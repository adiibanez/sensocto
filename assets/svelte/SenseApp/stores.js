import { writable } from 'svelte/store';

export const autostart = writable(false);

export const usersettings = writable({
    autostart: false,
    deviceName: ''
});

// Global BLE device state that persists across LiveView navigations
// We use window object to ensure truly global state across component remounts
if (!window.__sensocto_ble_state) {
    window.__sensocto_ble_state = {
        devices: [],
        deviceCharacteristics: {},
        characteristicValues: {},
        characteristicHandlers: new Map() // Maps characteristic UUID to handler function
    };
}

// Svelte stores that sync with the global window state
function createBleDevicesStore() {
    const { subscribe, set, update } = writable(window.__sensocto_ble_state.devices);

    return {
        subscribe,
        set: (value) => {
            window.__sensocto_ble_state.devices = value;
            set(value);
        },
        update: (fn) => {
            update(current => {
                const newValue = fn(current);
                window.__sensocto_ble_state.devices = newValue;
                return newValue;
            });
        },
        add: (device) => {
            update(devices => {
                // Check if device already exists
                const exists = devices.some(d => d.id === device.id);
                if (!exists) {
                    const newDevices = [...devices, device];
                    window.__sensocto_ble_state.devices = newDevices;
                    return newDevices;
                }
                return devices;
            });
        },
        remove: (device) => {
            update(devices => {
                const newDevices = devices.filter(d => d.id !== device.id);
                window.__sensocto_ble_state.devices = newDevices;
                return newDevices;
            });
        },
        getGlobal: () => window.__sensocto_ble_state.devices
    };
}

function createBleCharacteristicsStore() {
    const { subscribe, set, update } = writable(window.__sensocto_ble_state.deviceCharacteristics);

    return {
        subscribe,
        set: (value) => {
            window.__sensocto_ble_state.deviceCharacteristics = value;
            set(value);
        },
        update: (fn) => {
            update(current => {
                const newValue = fn(current);
                window.__sensocto_ble_state.deviceCharacteristics = newValue;
                return newValue;
            });
        },
        setForDevice: (deviceId, characteristics) => {
            update(current => {
                const newValue = { ...current, [deviceId]: characteristics };
                window.__sensocto_ble_state.deviceCharacteristics = newValue;
                return newValue;
            });
        },
        getGlobal: () => window.__sensocto_ble_state.deviceCharacteristics
    };
}

function createBleValuesStore() {
    const { subscribe, set, update } = writable(window.__sensocto_ble_state.characteristicValues);

    return {
        subscribe,
        set: (value) => {
            window.__sensocto_ble_state.characteristicValues = value;
            set(value);
        },
        update: (fn) => {
            update(current => {
                const newValue = fn(current);
                window.__sensocto_ble_state.characteristicValues = newValue;
                return newValue;
            });
        },
        setValue: (uuid, value) => {
            update(current => {
                const newValue = { ...current, [uuid]: value };
                window.__sensocto_ble_state.characteristicValues = newValue;
                return newValue;
            });
        },
        getGlobal: () => window.__sensocto_ble_state.characteristicValues
    };
}

// Stores for BLE device management - persist across LiveView navigations
export const bleDevices = createBleDevicesStore();
export const bleCharacteristics = createBleCharacteristicsStore();
export const bleValues = createBleValuesStore();

// Helper to get/set characteristic handlers (for re-subscribing after navigation)
export const bleHandlers = {
    set: (uuid, handler) => {
        window.__sensocto_ble_state.characteristicHandlers.set(uuid, handler);
    },
    get: (uuid) => {
        return window.__sensocto_ble_state.characteristicHandlers.get(uuid);
    },
    delete: (uuid) => {
        window.__sensocto_ble_state.characteristicHandlers.delete(uuid);
    },
    getAll: () => window.__sensocto_ble_state.characteristicHandlers
};