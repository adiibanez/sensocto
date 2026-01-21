import { writable, get } from 'svelte/store';

export const autostart = writable(false);

export const usersettings = writable({
    autostart: false,
    deviceName: ''
});

// ============================================================================
// SENSOR SETTINGS - Per-sensor persistence with localStorage
// ============================================================================

const SENSOR_SETTINGS_KEY = 'sensocto_sensor_settings';

// Default sensor settings
// Note: 'configured' tracks if user has ever interacted with the sensor
// This distinguishes between "never touched" (allow autostart fallback) and "explicitly disabled"
const DEFAULT_SENSOR_SETTINGS = {
    imu: { enabled: false, configured: false },
    geolocation: { enabled: false, configured: false },
    pose: { enabled: false, configured: false },
    battery: { enabled: false, configured: false },
    bluetooth: { enabled: false, configured: false },
    richPresence: { enabled: false, configured: false }
};

// Load settings from localStorage
function loadSensorSettings() {
    try {
        const stored = localStorage.getItem(SENSOR_SETTINGS_KEY);
        if (stored) {
            const parsed = JSON.parse(stored);
            // Merge with defaults to ensure all sensors have settings
            return { ...DEFAULT_SENSOR_SETTINGS, ...parsed };
        }
    } catch (e) {
        console.warn('Failed to load sensor settings from localStorage:', e);
    }
    return { ...DEFAULT_SENSOR_SETTINGS };
}

// Save settings to localStorage
function saveSensorSettings(settings) {
    try {
        localStorage.setItem(SENSOR_SETTINGS_KEY, JSON.stringify(settings));
    } catch (e) {
        console.warn('Failed to save sensor settings to localStorage:', e);
    }
}

// Create sensor settings store with localStorage persistence
function createSensorSettingsStore() {
    const initial = loadSensorSettings();
    const { subscribe, set, update } = writable(initial);

    return {
        subscribe,
        set: (value) => {
            saveSensorSettings(value);
            set(value);
        },
        update: (fn) => {
            update(current => {
                const newValue = fn(current);
                saveSensorSettings(newValue);
                return newValue;
            });
        },
        // Helper to enable/disable a specific sensor
        // Also marks the sensor as 'configured' so we know user has interacted with it
        setSensorEnabled: (sensorId, enabled) => {
            update(current => {
                const newValue = {
                    ...current,
                    [sensorId]: { ...current[sensorId], enabled, configured: true }
                };
                saveSensorSettings(newValue);
                return newValue;
            });
        },
        // Helper to check if a sensor is enabled
        isSensorEnabled: (sensorId) => {
            const current = get({ subscribe });
            return current[sensorId]?.enabled ?? false;
        },
        // Helper to check if a sensor has ever been configured by the user
        isSensorConfigured: (sensorId) => {
            const current = get({ subscribe });
            return current[sensorId]?.configured ?? false;
        },
        // Reset all settings to defaults
        reset: () => {
            saveSensorSettings(DEFAULT_SENSOR_SETTINGS);
            set({ ...DEFAULT_SENSOR_SETTINGS });
        }
    };
}

export const sensorSettings = createSensorSettingsStore();

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