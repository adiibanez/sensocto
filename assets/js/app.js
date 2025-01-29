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
import logger from "./logger.js"
// import Hooks from "./hooks"
import { getHooks } from "live_svelte"
import * as Components from "../svelte/**/*.svelte"

window.workerStorage = new Worker('/assets/worker-storage.js?' + Math.random());
let Hooks = {}

Hooks.ResizeDetection = {
  isResizing() {
    const mainElement = document.getElementById("main");
    if (!mainElement) return false;
    return mainElement.classList.contains('resizing');
  },
  mounted() {
    //logger.log("Hooks.ResizeDetection", "ResizeDetection Mounted!");

    let resizeStartTime = 0;
    let resizeTotalDuration = 0;
    let isResizing = false;

    window.addEventListener('resize', function () {
      //logger.log("Hooks.ResizeDetection", 'Resize detected!');
      if (!isResizing) {
        isResizing = true
        resizeStartTime = performance.now();
        document.querySelector("body").classList.add('resizing');
        //logger.log("Hooks.ResizeDetection", 'Resize: ', this.document.getElementById("main").classList);
      }
    }, { passive: true });

    window.addEventListener('resizeend', function () {
      //logger.log("Hooks.ResizeDetection", 'Resizeend detected!');

      if (isResizing) {
        isResizing = false
        const resizeEndTime = performance.now();
        const resizeDuration = resizeEndTime - resizeStartTime
        resizeTotalDuration += resizeDuration
        //logger.log("Hooks.ResizeDetection", `Resize duration: ${resizeDuration.toFixed(2)}ms, Total duration: ${resizeTotalDuration.toFixed(2)}ms`);
        document.querySelector("body").classList.remove('resizing');
        //logger.log("Hooks.ResizeDetection", 'Resizeendt: ', this.document.getElementById("main").classList);

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
    logger.log("Hooks.ResizeDetection", "ResizeDetection Destroyed!");
  }
}

Hooks.ConnectionHandler = {
  disconnected(event) {
    logger.log("Hooks.ConnectionHandler", "disconnected", event);
  },
  connected(event) {
    logger.log("Hooks.ConnectionHandler", "connected", event);
  }
}

Hooks.SensorDataAccumulator = {

  workerEventListener(event) {
    const { type, data } = event;
    logger.log("Hooks.SensorDataAccumulator", "WORKER event", type, data);

    const workerEvent = new CustomEvent('storage-worker-event', { id: data.id, detail: event.data });
    window.dispatchEvent(workerEvent);
  },

  mounted() {

    workerStorage.postMessage({ type: 'clear-data', data: { id: this.el.dataset.sensor_id + "_" + this.el.dataset.attribute_id } });

    if ('pushEvent' in this) {

      this.handleEvent("measurement", (measurement) => {
        let identifier = measurement.sensor_id + "_" + measurement.attribute_id;
        logger.log("Hooks.SensorDataAccumulator", "handleEvent measurement", identifier, measurement);
        const accumulatorEvent = new CustomEvent('accumulator-data-event', { id: identifier, detail: { data: measurement, id: identifier } });
        window.dispatchEvent(accumulatorEvent);
      });

      const payload = { "id": this.el.dataset.sensor_id, "attribute_id": this.el.dataset.attribute_id };
      logger.log("Hooks.SensorDataAccumulator", "pushEvent seeddata", payload);

      this.handleEvent("seeddata", (seed) => {
        console.log("Hooks.SensorDataAccumulator", "seed-data", seed);

        workerStorage.postMessage({ type: 'seed-data', data: { id: seed.sensor_id + "_" + seed.attribute_id, seedData: seed.data } });
        const seedEvent = new CustomEvent('seeddata-event', { id: seed.sensor_id + "_" + seed.attribute_id, detail: seed });
        window.dispatchEvent(seedEvent);
      });

      this.pushEvent("request-seed-data", payload);
    } else {
      logger.log("Hooks.SensorDataAccumulator", 'liveSocket', liveSocket);
    }

    resizeElements();
  },

  destroyed() {
    workerStorage.postMessage({ type: 'clear-data', data: { id: this.el.dataset.sensor_id + "_" + this.el.dataset.attribute_id } });
  },



  updated() {

    //logger.log("Hooks.SensorDataAccumulator", "SensorDataAccumulator: Update event", typeof this.el.dataset.append, this.el.dataset.append);

    if (false && this.el.dataset.append) {
      try {

        let identifier = this.el.dataset.sensor_id + "_" + this.el.dataset.attribute_id;

        logger.log("Hooks.SensorDataAccumulator", "SensorDataAccumulator: About to send accumulator-data-event", identifier);
        appendData = JSON.parse(this.el.dataset.append);
        // weird sparkline doesn't see the first id TODO debug resp, normalize with storage worker event

        const accumulatorEvent = new CustomEvent('accumulator-data-event', { id: identifier, detail: { data: appendData, id: identifier } });
        window.dispatchEvent(accumulatorEvent);
      } catch (e) {
        logger.log("Hooks.SensorDataAccumulator", 'accumulator parsing error', this.el.dataset.append, e);
      }
    }
  }
}
// add one listener for all components
window.addEventListener('worker-requesthandler-event', function (event) {
  logger.log("Hooks.SensorDataAccumulator", 'worker-requesthandler-event', event.type, event.detail);
  workerStorage.postMessage({ type: event.detail.type, data: event.detail.data });
}, false);



function resizeElements() {
  const allSparklines = document.querySelectorAll('.resizeable'); // Correct custom element tag.

  allSparklines.forEach(element => {
    const parentWidth = element.parentElement.offsetWidth;
    const parentHeight = element.parentElement.offsetHeight;
    logger.log("Element Resizer", element.id, parentWidth, parentHeight); // Log it.
    element.setAttribute('width', parentWidth); // Use setAttribute to change width
    //element.setAttribute('height', parentHeight); // Also set height to parent, if required.
  });
}

window.addEventListener('resizeend', resizeElements, { passive: true });


// Also set it up on DOMContentLoaded, for correct initial loading.
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', resizeElements);
} else {
  resizeElements();
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