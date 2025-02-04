
let enabled = false;

let enabledComponents = [
    // "SensorDataService",
    // "Hooks.SensorDataAccumulator",
    //     "ChartJS",
    //"ECGVisualization",
    //     "IMUClient",
    // "ScaledPoints", "Sparkline",
    // "BluetoothClient",
    // "SensorService",
    // "SensorDataService",
    // "IndexedDB",
    // "IndexedDB.Worker",
];

export function setLogging(value) {
    enabled = !!value;
}
// Added new argument to pass component Name
export function log(componentName, message, ...args) {
    if (enabled || enabledComponents.indexOf(componentName) > -1) {
        console.log(`[${componentName}]: ${message}`, ...args);
    }
}

export default logger = {
    setLogging,
    log,
};
