// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import topbar from "../vendor/topbar"
// import Hooks from "./hooks"
import { getHooks } from "live_svelte"
import * as Components from "../svelte/**/*.svelte"

window.workerStorage = new Worker('./assets/worker-storage.js?' + Math.random());
const debug = true;

let Hooks = {}

Hooks.ResizeDetection = {
  isResizing() {
    const mainElement = document.getElementById("main");
    if (!mainElement) return false;
    return mainElement.classList.contains('resizing');
  },
  mounted() {
    console.log("ResizeDetection Mounted!");

    let resizeStartTime = 0;
    let resizeTotalDuration = 0;
    let isResizing = false;

    window.addEventListener('resize', function () {
      if (debug) console.log('Resize detected!');
      if (!isResizing) {
        isResizing = true
        resizeStartTime = performance.now();
        this.document.getElementById("main").classList.add('resizing');
        if (debug) console.log('Resize: ', this.document.getElementById("main").classList);
      }
    }, { passive: true });

    window.addEventListener('resizeend', function () {
      console.log('Resizeend detected!');
      if (isResizing) {
        isResizing = false
        const resizeEndTime = performance.now();
        const resizeDuration = resizeEndTime - resizeStartTime
        resizeTotalDuration += resizeDuration
        if (debug) console.log(`Resize duration: ${resizeDuration.toFixed(2)}ms, Total duration: ${resizeTotalDuration.toFixed(2)}ms`);
        this.document.getElementById("main").classList.remove('resizing');
        if (debug) console.log('Resizeendt: ', this.document.getElementById("main").classList);

        // redraw sparklines
        //new SimpleSparkLineChart('.sparkline');
      }

    }, { passive: true });

    let resizeTimer;
    window.addEventListener('resize', function () {
      clearTimeout(resizeTimer);
      resizeTimer = setTimeout(function () {
        window.dispatchEvent(new Event('resizeend'));
      }, 50);
    }, { passive: true });

  },
  destroyed() {
    console.log("ResizeDetection Destroyed!");
  }
}

Hooks.SensorDataAccumulator = {

  workerEventListener(event) {
    const { type, data } = event;
    console.log("Worker event", type, data);

    const workerEvent = new CustomEvent('storage-worker-event', { id: data.id, detail: event.data });
    window.dispatchEvent(workerEvent);
  },

  mounted() {
    const sensorId = this.el.getAttribute("id");
    workerStorage.postMessage({ type: 'clear-data', data: { id: sensorId } });

    if ('pushEvent' in this) {
      this.pushEvent("request-seed-data", {"id": this.el.getAttribute('id')});
    } else {
      console.log('liveSocket', liveSocket);
    }

  },

  destroyed() {
    const sensorId = this.el.getAttribute("id");
    workerStorage.postMessage({ type: 'clear-data', data: { id: sensorId } });
  },

  updated() {
    const sensorId = this.el.getAttribute("id");

    const sparklineNewId = 'sparkline_element-' + sensorId;
    let sparkLineNew = document.getElementById(sparklineNewId);

    if (debug) console.log("DIV sensor updated", this.el.dataset.append);
    if (sparkLineNew && this.el.dataset.append != undefined) {

      const isLoading = sparkLineNew.getAttribute("is_loading");

      appendDataArray = JSON.parse(this.el.dataset.append);
      const requestType = (isLoading) ? 'append-read-data' : 'append-data';

      if (debug) console.log("Sparkline status", requestType, 'loading: ' + isLoading, typeof appendDataArray);

      if (appendDataArray && appendDataArray.timestamp && appendDataArray.value) {
        console.log("Going to request storage worker: ", requestType, appendDataArray);
        workerStorage.postMessage({ type: requestType, data: { id: sensorId, payload: appendDataArray, maxLength: sparkLineNew.maxlength } });
      }
    }
  }
}

workerStorage.addEventListener('message', Hooks.SensorDataAccumulator.workerEventListener);

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

let mergedHooks = { ...getHooks(Components), ...Hooks };

let liveSocket = new LiveSocket("/live", Socket, { hooks: mergedHooks, params: { _csrf_token: csrfToken } })

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" })
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket