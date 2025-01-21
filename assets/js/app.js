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
        new SimpleSparkLineChart('.sparkline');
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

    const updateSparkLineNew = function (id, values) {
      const sparkLineNewId = "sparkline_element-" + id;
      const loadingElementId = "loading-" + id;
      const sparklineNewElement = document.getElementById(sparkLineNewId);

      if (sparklineNewElement) {
        if (debug) console.log('updateSparkLineNew', sparkLineNewId, sparklineNewElement.dataset.length);
        if (Array.isArray(values) && values.length > 0) {
          sparklineNewElement.setAttribute("data", JSON.stringify(values));
          //sparklineNewElement.setAttribute("appenddata", JSON.stringify(values));

          loadingElementClassElement = document.getElementById(loadingElementId);
          if(loadingElementClassElement && !loadingElementClassElement.classList.contains("hidden")){
            loadingElementClassElement.classList.add("hidden");
          }

          sparklineNewElement.classList.remove("hidden");

          const updateEvent = new CustomEvent('dataupdate', { id: id, detail: values });
          window.dispatchEvent(updateEvent);
        }
      } else {
        //console.warn("Sparkline element not found: ", id, "sparklineElementSelector: #" + sparkLineNewId);
      }
    }

    const updateSparkLine = function (id, values) {
      //const sparklineElementSelector = `[data-sensor_id="${id}"] .sparkline`
      const sparkLineId = "sparkline-" + id;
      if (debug) console.log('updateSparkLine', sparkLineId);
      const sparklineElement = document.getElementById(sparkLineId);

      if (sparklineElement) {
        if (Array.isArray(values) && values.length > 0) {
          sparklineElement.dataset.values = JSON.stringify(values);
          new SimpleSparkLineChart("#" + sparkLineId)
          sparklineElement.classList.remove("hidden");
        }
      } else {
        //console.warn("Sparkline not found: ", id, "sparklineElementSelector: #" + sparkLineId);
      }
    }

    const { type, data } = event.data;

    if (event.data.type === 'updated-data') {
      if (debug) console.log('workerStorage Updated data result: ', event.data);
      if (Array.isArray(data.result)) {

        updateSparkLine(data.id, data.result);
        updateSparkLineNew(data.id, data.result)

        //const updateEvent = new CustomEvent('sparkline-update', { detail: { id: data.id, result: data.result } });
        //window.dispatchEvent(updateEvent);
      }
    }

    if (event.data.type === 'append-data-result') {
      if (debug) console.log('workerStorage Append data result: ', event);
    }

    if (event.data.type === 'append-data-error') {
      console.log('workerStorage Append data error: ', event);
    }

    if (event.data.type === 'clear-data-result') {
      const sensorId = event.data.data.id;
    } else if (event.data.type === 'clear-data-error') {
      console.error('workerStorage Clear data error: ', event);
    }

  },

  mounted() {
    const sensorId = this.el.getAttribute("id");
    workerStorage.postMessage({ type: 'clear-data', data: { id: sensorId } });
  },

  destroyed() {
    const sensorId = this.el.getAttribute("id");
    workerStorage.postMessage({ type: 'clear-data', data: { id: sensorId } });
  },

  updated() {
    const sensorId = this.el.getAttribute("id");

    if (debug) console.log("DIV sensor updated", this.el.dataset);

    const sparklineNewId = 'sparkline_element-' + sensorId;
    let sparkLineNew = document.getElementById(sparklineNewId);
    if (sparkLineNew && sparkLineNew.dataset.append != undefined) {

      if (debug) console.log("sparkline append message starting", sparkLineNew.maxlength);
      workerStorage.postMessage({ type: 'append-data', data: { id: sensorId, payload: JSON.parse(sparkLineNew.dataset.append), maxLength: sparkLineNew.maxlength } });

      var el = this.el;
      function updateWidth() {
        const newWidth = Math.floor(el.offsetWidth * 0.9);
        //console.log("resize: ", sparkLineId, sparkLine);
        sparkLineNew = document.getElementById(sparklineNewId);
        if (sparkLineNew) {
          sparkLineNew.setAttribute("width", newWidth);//("data-width", newWidth);
          sparkLineNew.maxlength = newWidth;

          console.log("resize: ", sparkLineNew.width, sparkLineNew.dataset.maxlength);
          // sparkLineNew.setAttribute("data-width", newWidth);//("data-width", newWidth);
        }
      }

      updateWidth() //initial update
      window.addEventListener("resizeend", updateWidth);

    }


    const sparkLine = document.getElementById('sparkline-' + sensorId);

    if (sparkLine && sparkLine.dataset.append != undefined) {

      workerStorage.postMessage({ type: 'append-data', data: { id: sensorId, payload: JSON.parse(sparkLine.dataset.append), maxLength: sparkLine.dataset.maxlength } });

      let sparkLineWidth = this.el.offsetWidth * 0.9;

      const sparkLineId = "sparkline-" + sensorId;

      let el = this.el;

      function updateWidth() {
        const newWidth = el.offsetWidth * 0.9;
        let sparkLine = document.querySelector('#' + sparkLineId);
        //console.log("resize: ", sparkLineId, sparkLine);
        if (sparkLine) {
          sparkLine.dataset.width = newWidth;//("data-width", newWidth);
          new SimpleSparkLineChart('#' + sparkLineId);
        }
      }

      updateWidth() //initial update
      window.addEventListener("resizeend", updateWidth);

      //this.el.dataset.accumulated.push(this.el.dataset.append);
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