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

window.workerGui = new Worker('./assets/worker-gui.js');
window.workerStorage = new Worker('./assets/worker-storage.js');
window.workerStorageAppender = new Worker('./assets/worker-storage.js');

//import * as SimpleSparkLineChart from "simple-sparkline-chart";
//import {SimpleSparkLineChart} from "simple-sparkline-chart";

window.console.log = function () {
};

let Hooks = {}

Hooks.Hello = {
  mounted() {
    console.log("Mounted!")
  },
  updated() {
    console.log("Updated!")
  }
}

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
      console.log('Resize detected!');
      if (!isResizing) {
        isResizing = true
        resizeStartTime = performance.now();
        this.document.getElementById("main").classList.add('resizing');
        console.log('Resize: ', this.document.getElementById("main").classList);
      }
    }, { passive: true });

    window.addEventListener('resizeend', function () {
      console.log('Resizeend detected!');
      if (isResizing) {
        isResizing = false
        const resizeEndTime = performance.now();
        const resizeDuration = resizeEndTime - resizeStartTime
        resizeTotalDuration += resizeDuration
        console.log(`Resize duration: ${resizeDuration.toFixed(2)}ms, Total duration: ${resizeTotalDuration.toFixed(2)}ms`);
        this.document.getElementById("main").classList.remove('resizing');
        console.log('Resizeendt: ', this.document.getElementById("main").classList);
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

  },



  workerEventListenerOld(event) {
    const { type, data } = event.data;
    if (type === 'accumulation-result') {
      const { accumulatedSelector, sparkLineSelector, accumulatedString, maxLength, elapsedTime } = data;
      //console.log('Worker Event Listener Accumulation Result: ', data);

      const accumulatedElement = document.querySelector(accumulatedSelector);
      if (accumulatedElement && accumulatedElement.dataset && accumulatedElement.dataset.values) {
        //console.log('Updating accumulation element ' + accumulatedSelector );
        accumulatedElement.dataset.values = accumulatedString;
      } else {
        console.log('No accumulatedElement found for' + accumulatedSelector);
      }

      const sparklineElement = document.querySelector(sparkLineSelector);
      if (sparklineElement && sparklineElement.dataset && sparklineElement.dataset.values) {
        //console.log('Updating data and initializing SimpleSparkLineChart ' + sparkLineSelector );
        sparklineElement.dataset.values = accumulatedString;
        if (!Hooks.ResizeDetection.isResizing()) {
          new SimpleSparkLineChart(sparkLineSelector);
        }
      } else {
        console.log('No sparklineElement found for ' + sparkLineSelector);
      }

    } else {
      console.log(type, event);
    }
  },
  mounted() {

    const sensorId = this.el.getAttribute("id");
    const accumulatedDataContainer = document.getElementById(
      "accumulated-data"
    );

    // Create and insert the accumulation element
    const accumulationElement = document.createElement("div");
    accumulationElement.className = `accumulated-data-${sensorId}`;
    accumulationElement.dataset.values = JSON.stringify([]);
    accumulatedDataContainer.appendChild(accumulationElement);
    //this.accumulationElement = accumulationElement;

  },

  updatedOld() {
    const sensorId = this.el.getAttribute("id");
    accumulationElementId = `accumulated-data-${sensorId}`;

    let accumulationElement = document.querySelector('.' + accumulationElementId);

    if (accumulationElement && accumulationElement.dataset && accumulationElement.dataset.values) {

      //let accumulatedData = JSON.parse(accumulationElement.dataset.values)
      const sparkLineId = "sparkline-" + sensorId;

      if (this.el.dataset.append) {

        const dataToProcess = {
          accumulatedSelector: '.' + accumulationElementId,
          sparkLineSelector: '.' + sparkLineId,
          accumulatedString: accumulationElement.dataset.values,
          appendString: this.el.dataset.append,
          maxLength: this.el.dataset.maxlength
        }
        workerGui.postMessage({ type: 'process-accumulation', data: dataToProcess });

        let sparkLineWidth = this.el.offsetWidth * 0.9;

        const sparkLine = document.createElement("div");
        sparkLine.setAttribute("class", "sparkline " + sparkLineId);
        sparkLine.setAttribute("data-width", sparkLineWidth);

        sparkLine.setAttribute("data-color-stroke", "#ffc107");
        sparkLine.setAttribute("data-color-filled", "#ffc107");
        sparkLine.setAttribute("data-filled", "0.1");
        sparkLine.setAttribute("data-stroke-width", "2");
        sparkLine.setAttribute("data-tooltip", "bottom");
        sparkLine.setAttribute("data-aria-label", "Tüderlidrü ... ");

        var element = this.el;

        sparkLine.dataset.values = accumulationElement.dataset.values;
        this.el.appendChild(sparkLine);
        //console.log("Sparkline", sparkLine);

        var updatingWidth = false;

        function updateWidth() {

          if (updatingWidth) return;
          updatingWidth = true;

          const newWidth = element.offsetWidth * 0.9;
          let sparkLine = document.querySelector('.' + sparkLineId);
          //console.log("resize: ", sparkLineId, sparkLine);
          if (sparkLine) {
            sparkLine.dataset.width = newWidth;//("data-width", newWidth);
            //const sparkLines = document.querySelectorAll('.sparkline');
            if (!Hooks.ResizeDetection.isResizing) {
              new SimpleSparkLineChart(".sparkline");
            }
          }
          updatingWidth = false;
        }

        updateWidth() //initial update

        if (sparkLine.dataset.resizerRegistered !== true && document.querySelector('body').dataset.sparkLineResizingLock !== true) {
          window.addEventListener("resize", updateWidth);
          sparkLine.dataset.resizerRegistered = true;
          document.querySelector('body').dataset.sparkLineResizingLock = true;
        }

        const scriptElement = document.createElement("script")
        scriptElement.textContent = "new SimpleSparkLineChart('." + sparkLineId + "');";
        this.el.appendChild(scriptElement);

      } else {
        console.log('DOM element accumulation', accumulationElement);
      }


      //this.el.dataset.accumulated.push(this.el.dataset.append);
    }
  },

  updatedOld() {
    const sensorId = this.el.getAttribute("id");
    accumulationElementId = `accumulated-data-${sensorId}`;

    let accumulationElement = document.querySelector('.' + accumulationElementId);

    if (accumulationElement && accumulationElement.dataset && accumulationElement.dataset.values) {

      //let accumulatedData = JSON.parse(accumulationElement.dataset.values)
      const sparkLineId = "sparkline-" + sensorId;

      if (this.el.dataset.append) {

        const dataToProcess = {
          accumulatedSelector: '.' + accumulationElementId,
          sparkLineSelector: '.' + sparkLineId,
          accumulatedString: accumulationElement.dataset.values,
          appendString: this.el.dataset.append,
          maxLength: this.el.dataset.maxlength
        }
        workerGui.postMessage({ type: 'process-accumulation', data: dataToProcess });

        let sparkLineWidth = this.el.offsetWidth * 0.9;

        const sparkLine = document.createElement("div");
        sparkLine.setAttribute("class", "sparkline " + sparkLineId);
        sparkLine.setAttribute("data-width", sparkLineWidth);

        sparkLine.setAttribute("data-color-stroke", "#ffc107");
        sparkLine.setAttribute("data-color-filled", "#ffc107");
        sparkLine.setAttribute("data-filled", "0.1");
        sparkLine.setAttribute("data-stroke-width", "2");
        sparkLine.setAttribute("data-tooltip", "bottom");
        sparkLine.setAttribute("data-aria-label", "Tüderlidrü ... ");

        var element = this.el;

        sparkLine.dataset.values = accumulationElement.dataset.values;
        this.el.appendChild(sparkLine);
        //console.log("Sparkline", sparkLine);

        var updatingWidth = false;

        function updateWidth() {

          if (updatingWidth) return;
          updatingWidth = true;

          const newWidth = element.offsetWidth * 0.9;
          let sparkLine = document.querySelector('.' + sparkLineId);
          //console.log("resize: ", sparkLineId, sparkLine);
          if (sparkLine) {
            sparkLine.dataset.width = newWidth;//("data-width", newWidth);
            //const sparkLines = document.querySelectorAll('.sparkline');
            if (!Hooks.ResizeDetection.isResizing) {
              new SimpleSparkLineChart(".sparkline");
            }
          }
          updatingWidth = false;
        }

        updateWidth() //initial update

        if (sparkLine.dataset.resizerRegistered !== true && document.querySelector('body').dataset.sparkLineResizingLock !== true) {
          window.addEventListener("resize", updateWidth);
          sparkLine.dataset.resizerRegistered = true;
          document.querySelector('body').dataset.sparkLineResizingLock = true;
        }

        const scriptElement = document.createElement("script")
        scriptElement.textContent = "new SimpleSparkLineChart('." + sparkLineId + "');";
        this.el.appendChild(scriptElement);

      } else {
        console.log('DOM element accumulation', accumulationElement);
      }


      //this.el.dataset.accumulated.push(this.el.dataset.append);
    }
  }
}

workerGui.addEventListener('message', Hooks.SensorDataAccumulator.workerEventListener);


/*let Hooks = {
    SensorDataAccumulator: {
      updated() {
        console.log("The hook was updated!");
        console.log(this);  // Log the entire hook context
        console.log(this.textContent);  // Log the updated content
      }
    }
  };
*/
/*Hooks.SensorDataAccumulator = {
    mounted() {
        console.log("mounted");
    },
    updated() {
        console.log("updated");
    },
};*/


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