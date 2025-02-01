
let enabled = true;

export function setLogging(value) {
    enabled = !!value;
}
// Added new argument to pass component Name
export function log(componentName, message, ...args) {
    if (enabled) {
        console.log(`[${componentName}]: ${message}`, ...args);
    }
}

export default logger = {
    setLogging,
    log,
};
