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
// Import directly from hooks.svelte module to avoid svelte/server dependency (from render.js)
import { getHooks } from "../../deps/live_svelte/assets/js/live_svelte/hooks.svelte"
import * as Components from "../svelte/**/*.svelte"
//import * as Components from "../svelte/SenseApp.svelte"

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

// Room-related hooks
import { RoomStorage, CopyToClipboard, QRCode } from './hooks/room_storage.js';

// Attention tracking hooks for back-pressure control
import { AttentionTracker, SensorPinControl } from './hooks/attention_tracker.js';

// Video/Voice call hooks
import { CallHook, VideoTileHook, CallControlsHook } from './webrtc/call_hooks.js';

// Safari has limited support for module workers - wrap in try/catch to prevent app crash
try {
  window.workerStorage = new Worker('/assets/worker-storage.js?' + Math.random(), { type: 'module' });
} catch (e) {
  console.warn('Module worker not supported, falling back to inline worker simulation');
  // Create a mock worker for Safari that does nothing but doesn't break the app
  window.workerStorage = {
    postMessage: () => {},
    addEventListener: () => {},
    removeEventListener: () => {},
    terminate: () => {}
  };
}
let Hooks = {}

// Register room hooks
Hooks.RoomStorage = RoomStorage;
Hooks.CopyToClipboard = CopyToClipboard;
Hooks.QRCode = QRCode;

// Register attention tracking hooks
Hooks.AttentionTracker = AttentionTracker;
Hooks.SensorPinControl = SensorPinControl;

// ExpandOnHover hook - expands view mode when hovering over the expand button
// The expanded state is "sticky" - it persists after mouse leaves
Hooks.ExpandOnHover = {
  mounted() {
    this.el.addEventListener('mouseenter', () => {
      this.pushEvent("expand_view_mode", {});
    });
  }
};

// Register video/voice call hooks
Hooks.CallHook = CallHook;
Hooks.VideoTileHook = VideoTileHook;
Hooks.CallControlsHook = CallControlsHook;

// Vibrate hook - vibrates device when data-value changes
// Vibration duration is proportional to button number (button * 100ms)
// Sound is optional and only plays when data-play-sound="true" is set
Hooks.Vibrate = {
  mounted() {
    this.lastValue = this.el.dataset.value;
    this.audioContext = null;
  },

  updated() {
    const newValue = this.el.dataset.value;
    if (newValue !== this.lastValue) {
      this.lastValue = newValue;
      const buttonNumber = parseInt(newValue, 10) || 1;
      const vibrateDuration = buttonNumber * 100;
      if (navigator.vibrate) {
        navigator.vibrate(vibrateDuration);
      }
      // Only play sound if explicitly enabled via data-play-sound attribute
      if (this.el.dataset.playSound === 'true') {
        this.playBeep(vibrateDuration);
      }
    }
  },

  playBeep(duration = 100) {
    try {
      if (!this.audioContext) {
        this.audioContext = new (window.AudioContext || window.webkitAudioContext)();
      }
      const beepDuration = duration / 1000;
      const oscillator = this.audioContext.createOscillator();
      const gainNode = this.audioContext.createGain();
      oscillator.connect(gainNode);
      gainNode.connect(this.audioContext.destination);
      oscillator.frequency.value = 880;
      oscillator.type = 'sine';
      gainNode.gain.setValueAtTime(0.3, this.audioContext.currentTime);
      gainNode.gain.exponentialRampToValueAtTime(0.01, this.audioContext.currentTime + beepDuration);
      oscillator.start(this.audioContext.currentTime);
      oscillator.stop(this.audioContext.currentTime + beepDuration);
    } catch (e) {
      console.warn('[Vibrate] Could not play beep:', e);
    }
  }
};

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

// CompositeMeasurementHandler hook - receives server-pushed measurements for composite views
// and dispatches them as window events for Svelte components to consume
Hooks.CompositeMeasurementHandler = {
  mounted() {
    logger.log("Hooks.CompositeMeasurementHandler", "mounted");

    this.handleEvent("composite_measurement", (event) => {
      logger.log("Hooks.CompositeMeasurementHandler", "composite_measurement", event);
      const customEvent = new CustomEvent('composite-measurement-event', {
        detail: event
      });
      window.dispatchEvent(customEvent);
    });
  },

  destroyed() {
    logger.log("Hooks.CompositeMeasurementHandler", "destroyed");
  }
}

// FooterToolbar hook - handles mobile collapsible footer
Hooks.FooterToolbar = {
  mounted() {
    this.setupElements();
    this.isExpanded = false;
    this.setupEventListeners();
  },

  // Re-query elements - needed after LiveView DOM patches
  setupElements() {
    this.toggleBtn = document.getElementById('footer-toggle');
    this.content = document.getElementById('footer-content-mobile');
    this.chevron = this.el.querySelector('.footer-chevron');
  },

  setupEventListeners() {
    if (this.toggleBtn && !this.listenersAttached) {
      // Use both click and touchend for better mobile support
      this.handleToggle = (e) => {
        e.preventDefault();
        e.stopPropagation();
        this.toggle();
      };

      this.toggleBtn.addEventListener('click', this.handleToggle);
      // Add touchend for mobile devices that may not fire click reliably
      this.toggleBtn.addEventListener('touchend', this.handleToggle, { passive: false });
      this.listenersAttached = true;
    }
  },

  // Called by LiveView after DOM patches - crucial for state synchronization
  updated() {
    // Re-query elements in case they were re-rendered
    this.setupElements();

    // Restore visual state to match our tracked isExpanded state
    // This fixes the issue where LiveView patches reset the DOM but our state is stale
    this.applyState();

    // Re-attach listeners if needed (in case button was re-rendered)
    this.setupEventListeners();
  },

  toggle() {
    this.isExpanded = !this.isExpanded;
    this.applyState();
  },

  // Apply the current isExpanded state to the DOM
  applyState() {
    if (!this.content || !this.toggleBtn) {
      return;
    }

    if (this.isExpanded) {
      this.content.classList.remove('hidden');
      this.toggleBtn.setAttribute('aria-expanded', 'true');
      if (this.chevron) {
        this.chevron.style.transform = 'rotate(180deg)';
      }
    } else {
      this.content.classList.add('hidden');
      this.toggleBtn.setAttribute('aria-expanded', 'false');
      if (this.chevron) {
        this.chevron.style.transform = 'rotate(0deg)';
      }
    }
  },

  destroyed() {
    if (this.toggleBtn && this.handleToggle) {
      this.toggleBtn.removeEventListener('click', this.handleToggle);
      this.toggleBtn.removeEventListener('touchend', this.handleToggle);
    }
    this.listenersAttached = false;
  }
}

// TimeDiff hook - displays relative time that updates when data-timestamp changes
Hooks.TimeDiff = {
  mounted() {
    this.startTime = parseInt(this.el.dataset.timestamp);
    this.updateDisplay();
    this.startTimer();

    // Use MutationObserver to detect attribute changes since LiveView
    // may not trigger updated() for attribute-only changes
    this.observer = new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        if (mutation.type === 'attributes' && mutation.attributeName === 'data-timestamp') {
          const newTimestamp = parseInt(this.el.dataset.timestamp);
          if (newTimestamp !== this.startTime) {
            this.startTime = newTimestamp;
            this.clearTimer();
            this.updateDisplay();
            this.startTimer();
          }
        }
      }
    });
    this.observer.observe(this.el, { attributes: true });
  },

  updated() {
    const newTimestamp = parseInt(this.el.dataset.timestamp);
    if (newTimestamp !== this.startTime) {
      this.startTime = newTimestamp;
      this.clearTimer();
      this.updateDisplay();
      this.startTimer();
    }
  },

  destroyed() {
    this.clearTimer();
    if (this.observer) {
      this.observer.disconnect();
    }
  },

  clearTimer() {
    if (this.timerInterval) {
      clearInterval(this.timerInterval);
      this.timerInterval = null;
    }
  },

  startTimer() {
    const diff = Date.now() - this.startTime;
    // Choose interval based on how old the timestamp is
    const interval = diff < 1000 ? 100 : diff < 60000 ? 1000 : 60000;
    this.timerInterval = setInterval(() => this.updateDisplay(), interval);
  },

  updateDisplay() {
    const diff = Date.now() - this.startTime;
    let text;

    if (diff < 1000) {
      text = `${diff.toFixed(0)} ms`;
    } else if (diff < 60000) {
      text = `${(diff / 1000).toFixed(1)} secs`;
    } else if (diff < 3600000) {
      const mins = Math.floor(diff / 60000);
      text = `${mins} min${mins > 1 ? 's' : ''}`;
    } else if (diff < 86400000) {
      text = `${Math.floor(diff / 3600000)} hours`;
    } else {
      text = `${Math.floor(diff / 86400000)} days`;
    }

    this.el.textContent = text;
  }
}

// SystemMetricsRefresh hook - triggers periodic refresh of system metrics display
Hooks.SystemMetricsRefresh = {
  mounted() {
    this.interval = setInterval(() => {
      // pushEventTo targets the LiveComponent by its phx-target (the element itself)
      this.pushEventTo(this.el, "refresh", {});
    }, 5000);
  },
  destroyed() {
    if (this.interval) {
      clearInterval(this.interval);
    }
  }
}

// PulsatingLogo hook - makes logo pulsate based on system load multiplier
Hooks.PulsatingLogo = {
  mounted() {
    this.currentMultiplier = 1.0;
    this.beatInterval = null;

    this.updateFromMetrics();

    this.observer = new MutationObserver(() => {
      this.updateFromMetrics();
    });

    const metricsEl = document.querySelector('[id="system-metrics"]');
    if (metricsEl) {
      this.observer.observe(metricsEl, { childList: true, subtree: true, characterData: true });
    }

    this.refreshInterval = setInterval(() => this.updateFromMetrics(), 2000);
  },

  updateFromMetrics() {
    const metricsEl = document.querySelector('[id="system-metrics"]');
    if (!metricsEl) return;

    const multiplierText = metricsEl.textContent || '';
    const match = multiplierText.match(/x\s*([\d.]+)/);
    if (match) {
      const newMultiplier = parseFloat(match[1]);
      if (!isNaN(newMultiplier) && newMultiplier !== this.currentMultiplier) {
        this.currentMultiplier = newMultiplier;
        this.startPulsating(newMultiplier);
      }
    }
  },

  startPulsating(multiplier) {
    if (this.beatInterval) {
      clearInterval(this.beatInterval);
      this.beatInterval = null;
    }

    // Always pulsate, but at different rates based on load
    // When multiplier <= 1.0, pulsate very slowly (every 10 seconds)
    // When multiplier > 1.0, pulsate faster based on load
    const baseInterval = multiplier <= 1.0 ? 10000 : 2000;
    const msPerBeat = multiplier <= 1.0 ? baseInterval : baseInterval / multiplier;

    this.triggerPulse();

    this.beatInterval = setInterval(() => {
      this.triggerPulse();
    }, msPerBeat);
  },

  triggerPulse() {
    this.el.classList.add('pulsing');
    setTimeout(() => {
      this.el.classList.remove('pulsing');
    }, 200);
  },

  destroyed() {
    if (this.beatInterval) {
      clearInterval(this.beatInterval);
    }
    if (this.refreshInterval) {
      clearInterval(this.refreshInterval);
    }
    if (this.observer) {
      this.observer.disconnect();
    }
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
liveSocket.disableDebug();

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket