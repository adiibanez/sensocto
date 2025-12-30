let Hooks = {};

Hooks.SensorDataAccumulator = {
    mounted() {
        console.log("mounted");
    },
    updated() {
        console.log("updated");
    },
};

Hooks.SystemMetricsRefresh = {
    mounted() {
        this.interval = setInterval(() => {
            this.pushEvent("refresh", {});
        }, 5000);
    },
    destroyed() {
        if (this.interval) {
            clearInterval(this.interval);
        }
    },
};

export default Hooks;