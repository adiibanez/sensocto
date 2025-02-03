class SensoctoDataProvider {
    constructor(eventDispatcher, options = {}) {
        this.eventDispatcher = eventDispatcher; // Your existing event system
        this.dataSubscriptions = new Map(); // Store subscriptions: key => { updateInterval, dataCallback, transformCallback, timeoutId }
        this.options = options; // Global options
    }

    subscribe(key, dataCallback, updateInterval, transformCallback = null) {
        if (this.dataSubscriptions.has(key)) {
            console.warn(`Subscription with key ${key} already exists, unsubscribing old`)
            this.unsubscribe(key);
        }
        if (typeof dataCallback !== "function") {
            throw new Error("dataCallback must be a function")
        }

        const timeoutId = this._startUpdateCycle(key, dataCallback, updateInterval, transformCallback);
        this.dataSubscriptions.set(key, {
            updateInterval,
            dataCallback,
            transformCallback,
            timeoutId,
        });

    }

    unsubscribe(key) {
        const subscription = this.dataSubscriptions.get(key);
        if (subscription) {
            clearTimeout(subscription.timeoutId);
            this.dataSubscriptions.delete(key);
        } else {
            console.warn(`No subscription with key ${key}`);
        }
    }

    _startUpdateCycle(key, dataCallback, updateInterval, transformCallback) {
        const updateCycle = async () => {
            try {
                const newData = await dataCallback();
                const transformedData = transformCallback ? transformCallback(newData) : newData;
                this.eventDispatcher.dispatchEvent(key, transformedData); // Use your event system
            } catch (error) {
                console.error(`Error fetching data for key ${key}:`, error);
                // Optionally dispatch an error event
                this.eventDispatcher.dispatchEvent(`${key}:error`, error);
            }
            // Only trigger next cycle if still subscribed to.
            if (this.dataSubscriptions.has(key)) {
                const timeoutId = setTimeout(updateCycle, updateInterval);
                const currentSubscription = this.dataSubscriptions.get(key);
                if (currentSubscription) {
                    currentSubscription.timeoutId = timeoutId;
                }
            }
        };

        return setTimeout(updateCycle, 0); // Initial immediate trigger
    }
}


export default SensoctoDataProvider;