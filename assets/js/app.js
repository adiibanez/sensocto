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
//import * as Components from "../svelte/SenseApp.svelte"

//import init, { draw_sparkline } from "./wasm_sparkline_bg.js";

/*async function initSparklineWasm() {
  await init("/assets/wasm_sparkline_bg.wasm");
  wasmInitialized = true;
  logger.log(loggerCtxName, "Wasm initialized, yippie", draw_sparkline);
}*/

import {
  openDatabase,
  handleClearData,
  handleAppendData,
  handleAppendAndReadData,
  handleSeedData,
  handleGetLastTimestamp,
  handleGetAllLatestTimestamps,
  setDebug
} from './indexeddb.js';



window.workerStorage = new Worker('/assets/worker-storage.js?' + Math.random(), { type: 'module' });
let Hooks = {}


Hooks.Formless = {
  mounted() {

    console.log('Formless mount', this.el.dataset.sensor_id, this.el.dataset.attribute_id);

    this.el.addEventListener('change', event => {

      console.log('Formless change', this.el.dataset.event, this.el.dataset.sensor_id, this.el.dataset.attribute_id, this.el.value);

      const eventName = this.el.dataset.event
      const sensorId = this.el.dataset.sensor_id;
      const attributeId = this.el.dataset.attribute_id;

      const payload = {
        sensor_id: sensorId,
        attribute_id: attributeId,
        value: event.target.value
      };

      this.pushEvent(eventName, payload);
    })
  }
}

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

    const workerEvent = new CustomEvent('storage-worker-event', { id: data.sensor_id + "_" + data.attribute_id, detail: event.data });
    window.dispatchEvent(workerEvent);
  },

  mounted() {
    //workerStorage.postMessage({ type: 'clear-data', data: { sensor_id: this.el.dataset.sensor_id, attribute_id: this.el.dataset.attribute_id } });


    // handleGetAllLatestTimestamps().then((result) => {
    //   console.log("last timestamps for all keys:", result);
    // });

    // make sure we wait for server seed
    this.el.dataset.seeding = true;
    handleGetLastTimestamp(this.el.dataset.sensor_id, this.el.dataset.attribute_id).then((result) => {
      console.log("Last timestamp for ", this.el.dataset.sensor_id, this.el.dataset.attribute_id, result);

      const payload = {
        "sensor_id": this.el.dataset.sensor_id,
        "attribute_id": this.el.dataset.attribute_id,
        "from": result,
        "to": null,
        "limit": null
      };

      logger.log("Hooks.SensorDataAccumulator", "pushEvent seeddata", payload, result);

      this.handleEvent("seeddata", (seed) => {
        console.log("Hooks.SensorDataAccumulator", "seed-data", seed);

        let identifier_seed = seed.sensor_id + "_" + seed.attribute_id;

        if (seed.sensor_id == this.el.dataset.sensor_id && seed.attribute_id == this.el.dataset.attribute_id) {

          handleAppendAndReadData(seed.sensor_id, seed.attribute_id, seed).then((result) => {
            logger.log("Hooks.SensorDataAccumulator", "handleAppendAndReadData measurement", seed.sensor_id, seed.attribute_id, "Seed length: ", seed.length, "Result length: ", result.length);
            const seedEvent = new CustomEvent('seeddata-event', { id: identifier_seed, detail: { sensor_id: seed.sensor_id, attribute_id: seed.attribute_id, data: result } });
            window.dispatchEvent(seedEvent);
            this.el.dataset.seeding = false;
          });

          // workerStorage.postMessage({ type: 'seed-data', data: { sensor_id: this.el.dataset.sensor_id, attribute_id: this.el.dataset.attribute_id, seedData: seed.data } });

        }
      });

      this.pushEvent("request-seed-data", payload);
    });


    this.handleEvent("clear-attribute", (e) => {

      this.el.dataset.seeding = true;

      logger.log("Hooks.SensorDataAccumulator", "clear-attribute", e.sensor_id, e.attribute_id);
      handleClearData(e.sensor_id, e.attribute_id).then((result) => {
        const seedEvent = new CustomEvent('seeddata-event', { id: e.sensor_id + '_' + e.attribute_id, detail: { sensor_id: e.sensor_id, attribute_id: e.attribute_id, data: [] } });
        workerStorage.postMessage({ type: 'clear-data', data: { sensor_id: this.el.dataset.sensor_id, attribute_id: this.el.dataset.attribute_id } });
        window.dispatchEvent(seedEvent);

        this.el.dataset.seeding = false;
      });
    }
    );

    var hookElement = this.el;

    if ('pushEvent' in this && 'handleEvent' in this) {
      this.handleEvent("measurements_batch", (event) => {

        if (hookElement.dataset.seeding !== true && event.sensor_id == this.el.dataset.sensor_id) {
          // iterate over attributes and triage
          let uniqueAttributeIds = [...new Set(event.attributes.map(attribute => attribute.attribute_id))];

          uniqueAttributeIds.forEach(attributeId => {
            logger.log("Hooks.SensorDataAccumulator", "measurements_batch ", { attribute_id: attributeId, el_attribute_id: this.el.dataset.attribute_id }, event);
            if (event.sensor_id == this.el.dataset.sensor_id && attributeId == this.el.dataset.attribute_id) {
              let relevantAttributes = event.attributes.filter(attribute => attribute.attribute_id === attributeId);
              logger.log("Hooks.SensorDataAccumulator", "handleEvent BATCH measurement_batch", event.sensor_id, attributeId, relevantAttributes.length, relevantAttributes);
              const accumulatorEvent = new CustomEvent('accumulator-data-event', { detail: { sensor_id: event.sensor_id, attribute_id: attributeId, data: relevantAttributes } });
              window.dispatchEvent(accumulatorEvent);

              handleAppendData(event.sensor_id, attributeId, relevantAttributes).then((result) => {
                logger.log("Hooks.SensorDataAccumulator", " handleAppendData measurements_batch", event.sensor_id, attributeId, result);
              });
            }
          });
        }
      });

      this.handleEvent("measurement", (event) => {
        // match sensor_id and attribute_id, then push event
        if (hookElement.dataset.seeding !== true && event.sensor_id == this.el.dataset.sensor_id && event.attribute_id == this.el.dataset.attribute_id) {
          logger.log("Hooks.SensorDataAccumulator", "handleEvent SINGLE measurement", event.sensor_id, event.attribute_id, event);
          const accumulatorEvent = new CustomEvent('accumulator-data-event', { detail: { sensor_id: event.sensor_id, attribute_id: this.el.dataset.attribute_id, data: event } });
          window.dispatchEvent(accumulatorEvent);

          handleAppendData(event.sensor_id, event.attribute_id, event).then((result) => {
            logger.log("Hooks.SensorDataAccumulator", "handleAppendData measurement", event.sensor_id, event.attribute_id, result);
          });
        }
      }
      );

    } else {
      logger.log("Hooks.SensorDataAccumulator", 'liveSocket', liveSocket);
    }

    resizeElements();
  },

  destroyed() {



    //workerStorage.postMessage({ type: 'clear-data', data: { id: this.el.dataset.sensor_id + "_" + this.el.dataset.attribute_id } });
  },



  updated() {

  }
}
// add one listener for all components
window.addEventListener('worker-requesthandler-event', function (event) {
  logger.log("Hooks.SensorDataAccumulator", 'worker-requesthandler-event', event.type, event.detail);
  workerStorage.postMessage({ type: event.detail.type, data: event.detail.data });
}, false);



function resizeElements() {
  const allSparklines = document.querySelectorAll('.resizeable');

  allSparklines.forEach(element => {
    const parent = element.parentElement;
    if (!parent) {
      console.warn("Parent element not found for", element);
      return;
    }

    const computedStyle = getComputedStyle(parent);

    // Get padding and margin values
    const paddingLeft = parseFloat(computedStyle.paddingLeft) || 0;
    const paddingRight = parseFloat(computedStyle.paddingRight) || 0;
    const paddingTop = parseFloat(computedStyle.paddingTop) || 0;
    const paddingBottom = parseFloat(computedStyle.paddingBottom) || 0;

    const marginLeft = parseFloat(computedStyle.marginLeft) || 0;
    const marginRight = parseFloat(computedStyle.marginRight) || 0;
    const marginTop = parseFloat(computedStyle.marginTop) || 0;
    const marginBottom = parseFloat(computedStyle.marginBottom) || 0;

    // Calculate the inner width and height by subtracting padding and margins.
    const parentWidth = parent.offsetWidth - paddingLeft - paddingRight - marginLeft - marginRight;
    const parentHeight = parent.offsetHeight - paddingTop - paddingBottom - marginTop - marginBottom;

    // Calculate the available with based on padding and margin
    const availableWidth = parentWidth;
    const availableHeight = parentHeight;

    element.setAttribute('width', availableWidth);
    logger.log("Element Resizer", element.id, availableWidth, availableHeight, element.getAttribute("width"));
  });
}

window.addEventListener('resizeend', resizeElements, { passive: true });


// Also set it up on DOMContentLoaded, for correct initial loading.
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', resizeElements);
  //initSparklineWasm();r
} else {
  // initial graph resize
  resizeElements();
}



window.addEventListener("phx:live_reload:attached", ({ detail: reloader }) => {
  // Enable server log streaming to client.
  // Disable with reloader.disableServerLogs()
  reloader.enableServerLogs()
  window.liveReloader = reloader
  let keyDown
  window.addEventListener("keydown", (event) => keyDown = event.key)
  window.addEventListener("keyup", (_) => keyDown = null)
  window.addEventListener("click", (event) => {
    if (keyDown === "c") {
      event.preventDefault()
      event.stopImmediatePropagation()
      reloader.openEditorAtCaller(event.target)
    } else if (keyDown === "d") {
      event.preventDefault()
      event.stopImmediatePropagation()
      reloader.openEditorAtDef(event.target)
    }
  })
})


workerStorage.addEventListener('message', Hooks.SensorDataAccumulator.workerEventListener);

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

//let mergedHooks = { ...getHooks(Components), ...Hooks };
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