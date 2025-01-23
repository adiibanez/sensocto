
    let enabled = true;
    let enabledComponents = ["Sparkline"];

    export function setLogging(value) {
        enabled = !!value;
    }
    // Added new argument to pass component Name
    export function log(componentName, message, ...args) {
        if (enabled || enabledComponents.indexOf(componentName) > -1) {
            console.log(`[${componentName}]: ${message}`, ...args);
        }
    }

    export const logger = {
        setLogging,
        log,
    };
