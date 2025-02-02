<script>
    import {
        getContext,
        createEventDispatcher,
        onDestroy,
        onMount,
    } from "svelte";

    import { logger } from "../logger_svelte.js";

    let sensorService = getContext("sensorService");
    let loggerCtxName = "NetworkQualityMonitor";

    let newtworkStatusHistory = [];

    let lastNetworkStatus = "unknown";
    function isNetworkGood() {
        const networkInfo = getNetworkInfo();
        if (networkInfo.connectionType == "wifi") {
            return true;
        } else if (networkInfo.effectiveType == "4g") {
            return true;
        }
        return false;
    }

    function networkStateChanged(event) {
        logger.log(loggerCtxName, "Network state changed: ", event);
        /*const newNetworkStatus = isNetworkGood() ? "good" : "bad";

        if (newNetworkStatus != lastNetworkStatus) {
            channel.push("network_state_changed", {
                network_status: newNetworkStatus,
            });
            lastNetworkStatus = newNetworkStatus;
        }*/

        const networkData = {
            timestamp: new Date(),
            data: {},
        };

        if (navigator.connection.downlink !== undefined) {
            networkData.data.downlink = navigator.connection.downlink;
        }
        if (navigator.connection.downlinkMax !== undefined) {
            networkData.data.downlinkMax = navigator.connection.downlinkMax;
        }
        if (navigator.connection.effectiveType !== undefined) {
            networkData.data.effectiveType = navigator.connection.effectiveType;
        }
        if (navigator.connection.rtt !== undefined) {
            networkData.data.rtt = navigator.connection.rtt;
        }
        if (navigator.connection.saveData !== undefined) {
            networkData.data.saveData = navigator.connection.saveData;
        }
        if (navigator.connection.type !== undefined) {
            networkData.data.type = navigator.connection.type;
        }
        newtworkStatusHistory.push(networkData);
    }

    window.addEventListener("online", networkStateChanged);
    window.addEventListener("offline", networkStateChanged);
    if (navigator.connection) {
        logger.log(loggerCtxName, "navigator.connection is available");
        navigator.connection.addEventListener("change", networkStateChanged);
        networkStateChanged(); //Initial check.
    } else {
        logger.log(loggerCtxName, "navigator.connection is NOT available :(");
    }
</script>

{"Conn: " + ("connection" in navigator) ? "Yep" : "Nope"}
{JSON.stringify(newtworkStatusHistory, null, 2)}
