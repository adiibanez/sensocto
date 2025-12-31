/**
 * AttentionTracker Hook
 *
 * Tracks user attention on sensor attributes for back-pressure control.
 * Uses IntersectionObserver for viewport visibility and focus/click events
 * for active interaction detection.
 */

const DEBOUNCE_MS = 300;
// Hover is now immediate on first entry, debounce only prevents rapid re-entry
const HOVER_DEBOUNCE_MIN_MS = 50;   // Minimum debounce when system is responsive
const HOVER_DEBOUNCE_MAX_MS = 500;  // Maximum debounce when system is under load
const HOVER_BOOST_DURATION_MS = 2000;  // How long hover boost lasts after mouse leaves
const BATTERY_LOW_THRESHOLD = 0.30;
const BATTERY_CRITICAL_THRESHOLD = 0.15;

// Adaptive debouncing based on system responsiveness
let lastEventTime = 0;
let eventLatencies = [];
const MAX_LATENCY_SAMPLES = 10;

function getAdaptiveDebounce() {
  if (eventLatencies.length < 3) {
    return HOVER_DEBOUNCE_MIN_MS;
  }
  // Average latency of recent events
  const avgLatency = eventLatencies.reduce((a, b) => a + b, 0) / eventLatencies.length;
  // Scale debounce based on latency (higher latency = more debounce)
  const scaled = Math.min(HOVER_DEBOUNCE_MAX_MS, Math.max(HOVER_DEBOUNCE_MIN_MS, avgLatency * 2));
  return Math.round(scaled);
}

function recordEventLatency(startTime) {
  const latency = performance.now() - startTime;
  eventLatencies.push(latency);
  if (eventLatencies.length > MAX_LATENCY_SAMPLES) {
    eventLatencies.shift();
  }
}

export const AttentionTracker = {
  mounted() {
    this.observers = new Map();
    this.debounceTimers = new Map();
    this.focusedElements = new Set();
    this.viewedElements = new Set();
    this.hoveredElements = new Set();  // Track currently hovered elements
    this.hoverBoostTimers = new Map();  // Timers to expire hover boost
    this.hoverDebounceTimers = new Map();  // Debounce timers for hover events
    this.batteryState = 'normal';  // 'normal', 'low', 'critical'
    this.battery = null;

    // Set up intersection observer for visibility tracking
    this.intersectionObserver = new IntersectionObserver(
      (entries) => this.handleIntersection(entries),
      { threshold: 0.1, rootMargin: '50px' }
    );

    // Observe all attribute elements
    this.observeAttributes();

    // Set up focus tracking
    this.setupFocusTracking();

    // Set up page visibility tracking
    this.setupPageVisibility();

    // Set up battery tracking for energy awareness
    this.setupBatteryTracking();

    // Handle dynamic updates
    this.handleEvent("attributes_updated", () => {
      this.observeAttributes();
    });
  },

  updated() {
    // Re-observe attributes after LiveView updates the DOM
    // This ensures we track new/replaced elements
    this.observeAttributes();
  },

  destroyed() {
    // Clean up observers
    if (this.intersectionObserver) {
      this.intersectionObserver.disconnect();
    }

    // Clear all debounce timers
    this.debounceTimers.forEach(timer => clearTimeout(timer));
    this.debounceTimers.clear();

    // Clear hover debounce timers
    this.hoverDebounceTimers.forEach(timer => clearTimeout(timer));
    this.hoverDebounceTimers.clear();

    // Clear hover boost timers
    this.hoverBoostTimers.forEach(timer => clearTimeout(timer));
    this.hoverBoostTimers.clear();

    // Unregister all hover boosts
    this.hoveredElements.forEach(key => {
      const [sensorId, attributeId] = key.split(':');
      this.pushEvent("hover_leave", { sensor_id: sensorId, attribute_id: attributeId });
    });

    // Unregister all views
    this.viewedElements.forEach(key => {
      const [sensorId, attributeId] = key.split(':');
      this.pushEvent("view_leave", { sensor_id: sensorId, attribute_id: attributeId });
    });

    // Unregister all focus
    this.focusedElements.forEach(key => {
      const [sensorId, attributeId] = key.split(':');
      this.pushEvent("unfocus", { sensor_id: sensorId, attribute_id: attributeId });
    });
  },

  observeAttributes() {
    // Find all attribute elements with data-sensor_id and data-attribute_id
    const elements = this.el.querySelectorAll('[data-sensor_id][data-attribute_id]');

    elements.forEach(el => {
      const key = `${el.dataset.sensor_id}:${el.dataset.attribute_id}`;

      // Check if we're already observing this exact element (not just the key)
      const existingEl = this.observers.get(key);

      if (existingEl === el) {
        // Same element, already observing - skip
        return;
      }

      if (existingEl) {
        // Element changed - stop observing the old element
        this.intersectionObserver.unobserve(existingEl);
        // Keep the viewed state - don't remove from viewedElements
        // The new element will be observed and intersection callback will fire
      }

      this.observers.set(key, el);
      this.intersectionObserver.observe(el);

      // Add click and hover listeners (use named function to avoid duplicates)
      if (!el._attentionClickHandler) {
        el._attentionClickHandler = () => this.handleClick(el);
        el._attentionMouseEnterHandler = () => this.handleMouseEnter(el);
        el._attentionMouseLeaveHandler = () => this.handleMouseLeave(el);
        el.addEventListener('click', el._attentionClickHandler);
        el.addEventListener('mouseenter', el._attentionMouseEnterHandler);
        el.addEventListener('mouseleave', el._attentionMouseLeaveHandler);
      }
    });

    // Also track sensor-level hover on the container element itself
    // This enables attention tracking when hovering over the sensor header/tile
    this.setupSensorLevelTracking();
  },

  setupSensorLevelTracking() {
    // The hook element (this.el) may have data-sensor_id for sensor-level tracking
    const sensorId = this.el.dataset.sensor_id;
    if (!sensorId) return;

    // Only set up once
    if (this._sensorLevelTrackingSetup) return;
    this._sensorLevelTrackingSetup = true;

    // Track sensor-level hover using a synthetic "_sensor" attribute id
    // This enables hover attention even when mouse is over header/empty areas
    this.el.addEventListener('mouseenter', () => {
      this.handleSensorMouseEnter(sensorId);
    });

    this.el.addEventListener('mouseleave', () => {
      this.handleSensorMouseLeave(sensorId);
    });

    // Also observe the container for intersection (sensor visibility)
    this.intersectionObserver.observe(this.el);
    this.observers.set(`${sensorId}:_sensor`, this.el);
  },

  handleSensorMouseEnter(sensorId) {
    const key = `${sensorId}:_sensor`;
    const eventStart = performance.now();

    // Cancel any pending hover_leave (user re-entered before boost expired)
    if (this.hoverBoostTimers.has(key)) {
      clearTimeout(this.hoverBoostTimers.get(key));
      this.hoverBoostTimers.delete(key);
      return;
    }

    // Send hover event for ALL attributes of this sensor (boost them all)
    if (!this.hoveredElements.has(key)) {
      // Find all attribute elements and send hover_enter for each
      const elements = this.el.querySelectorAll('[data-sensor_id][data-attribute_id]');
      elements.forEach(el => {
        const attrKey = `${el.dataset.sensor_id}:${el.dataset.attribute_id}`;
        if (!this.hoveredElements.has(attrKey)) {
          this.pushEvent("hover_enter", {
            sensor_id: el.dataset.sensor_id,
            attribute_id: el.dataset.attribute_id
          });
          this.hoveredElements.add(attrKey);
        }
      });
      this.hoveredElements.add(key);
      recordEventLatency(eventStart);
    }
  },

  handleSensorMouseLeave(sensorId) {
    const key = `${sensorId}:_sensor`;

    // If we're tracking sensor-level hover, schedule the boost expiry
    if (this.hoveredElements.has(key)) {
      const boostDuration = Math.max(HOVER_BOOST_DURATION_MS, getAdaptiveDebounce() * 10);

      const timer = setTimeout(() => {
        if (this.hoveredElements.has(key)) {
          // Send hover_leave for all attributes
          const elements = this.el.querySelectorAll('[data-sensor_id][data-attribute_id]');
          elements.forEach(el => {
            const attrKey = `${el.dataset.sensor_id}:${el.dataset.attribute_id}`;
            if (this.hoveredElements.has(attrKey)) {
              this.pushEvent("hover_leave", {
                sensor_id: el.dataset.sensor_id,
                attribute_id: el.dataset.attribute_id
              });
              this.hoveredElements.delete(attrKey);
            }
          });
          this.hoveredElements.delete(key);
        }
        this.hoverBoostTimers.delete(key);
      }, boostDuration);
      this.hoverBoostTimers.set(key, timer);
    }
  },

  handleIntersection(entries) {
    entries.forEach(entry => {
      const el = entry.target;
      const sensorId = el.dataset.sensor_id;
      // For sensor container element (no attribute_id), use synthetic "_sensor"
      const attributeId = el.dataset.attribute_id || '_sensor';

      if (!sensorId) return;

      const key = `${sensorId}:${attributeId}`;

      // Ignore events for elements that are no longer the current observed element
      // This happens when LiveView replaces DOM elements during updates
      const currentEl = this.observers.get(key);
      if (currentEl !== el) {
        return;
      }

      // Handle sensor container separately (synthetic _sensor attribute)
      const isSensorContainer = attributeId === '_sensor';

      if (entry.isIntersecting) {
        // Element entered viewport
        if (!this.viewedElements.has(key)) {
          if (isSensorContainer) {
            // Sensor container visible - send view_enter for all child attributes
            const childElements = el.querySelectorAll('[data-sensor_id][data-attribute_id]');
            childElements.forEach(childEl => {
              const childKey = `${childEl.dataset.sensor_id}:${childEl.dataset.attribute_id}`;
              if (!this.viewedElements.has(childKey)) {
                this.debouncedPush(childKey, "view_enter", {
                  sensor_id: childEl.dataset.sensor_id,
                  attribute_id: childEl.dataset.attribute_id
                });
                this.viewedElements.add(childKey);
              }
            });
          } else {
            this.debouncedPush(key, "view_enter", { sensor_id: sensorId, attribute_id: attributeId });
          }
          this.viewedElements.add(key);
          // Mark that we've confirmed this element is visible
          el._confirmedVisible = true;
        }
      } else {
        // Element left viewport
        // Only fire view_leave if we previously confirmed the element was visible
        // This prevents spurious view_leave events when elements are first observed
        // but layout hasn't completed yet
        if (this.viewedElements.has(key) && el._confirmedVisible) {
          if (isSensorContainer) {
            // Sensor container left viewport - send view_leave for all child attributes
            const childElements = el.querySelectorAll('[data-sensor_id][data-attribute_id]');
            childElements.forEach(childEl => {
              const childKey = `${childEl.dataset.sensor_id}:${childEl.dataset.attribute_id}`;
              if (this.viewedElements.has(childKey)) {
                this.debouncedPush(childKey, "view_leave", {
                  sensor_id: childEl.dataset.sensor_id,
                  attribute_id: childEl.dataset.attribute_id
                });
                this.viewedElements.delete(childKey);
              }
            });
          } else {
            this.debouncedPush(key, "view_leave", { sensor_id: sensorId, attribute_id: attributeId });
          }
          this.viewedElements.delete(key);
          el._confirmedVisible = false;

          // Also remove focus if was focused (only for real attributes)
          if (!isSensorContainer && this.focusedElements.has(key)) {
            this.pushEvent("unfocus", { sensor_id: sensorId, attribute_id: attributeId });
            this.focusedElements.delete(key);
          }
        }
      }
    });
  },

  handleClick(el) {
    const sensorId = el.dataset.sensor_id;
    const attributeId = el.dataset.attribute_id;
    const key = `${sensorId}:${attributeId}`;

    if (!this.focusedElements.has(key)) {
      // Unfocus any previously focused element
      this.focusedElements.forEach(focusedKey => {
        if (focusedKey !== key) {
          const [prevSensorId, prevAttributeId] = focusedKey.split(':');
          this.pushEvent("unfocus", { sensor_id: prevSensorId, attribute_id: prevAttributeId });
        }
      });
      this.focusedElements.clear();

      // Focus this element
      this.pushEvent("focus", { sensor_id: sensorId, attribute_id: attributeId });
      this.focusedElements.add(key);
    }
  },

  handleMouseEnter(el) {
    const sensorId = el.dataset.sensor_id;
    const attributeId = el.dataset.attribute_id;
    const key = `${sensorId}:${attributeId}`;
    const eventStart = performance.now();

    // Ensure it's registered as viewed first
    if (!this.viewedElements.has(key)) {
      this.pushEvent("view_enter", { sensor_id: sensorId, attribute_id: attributeId });
      this.viewedElements.add(key);
    }

    // Cancel any pending hover_leave (user re-entered before boost expired)
    if (this.hoverBoostTimers.has(key)) {
      clearTimeout(this.hoverBoostTimers.get(key));
      this.hoverBoostTimers.delete(key);
      // User re-entered while still "boosted" - no need to send another event
      return;
    }

    // Cancel any pending hover debounce timer
    if (this.hoverDebounceTimers.has(key)) {
      clearTimeout(this.hoverDebounceTimers.get(key));
      this.hoverDebounceTimers.delete(key);
    }

    // Send hover event immediately if not already hovered
    // This makes the initial hover response instant
    if (!this.hoveredElements.has(key)) {
      this.pushEvent("hover_enter", { sensor_id: sensorId, attribute_id: attributeId });
      this.hoveredElements.add(key);
      recordEventLatency(eventStart);
    }
  },

  handleMouseLeave(el) {
    const sensorId = el.dataset.sensor_id;
    const attributeId = el.dataset.attribute_id;
    const key = `${sensorId}:${attributeId}`;

    // Cancel any pending hover_enter debounce (user left before it fired)
    if (this.hoverDebounceTimers.has(key)) {
      clearTimeout(this.hoverDebounceTimers.get(key));
      this.hoverDebounceTimers.delete(key);
    }

    // If we're currently tracking this as hovered, schedule the boost expiry
    if (this.hoveredElements.has(key)) {
      // Keep the hover boost active for a short duration after mouse leaves
      // This prevents flickering when moving between elements
      // Use adaptive duration based on system load
      const boostDuration = Math.max(HOVER_BOOST_DURATION_MS, getAdaptiveDebounce() * 10);

      const timer = setTimeout(() => {
        if (this.hoveredElements.has(key)) {
          this.pushEvent("hover_leave", { sensor_id: sensorId, attribute_id: attributeId });
          this.hoveredElements.delete(key);
        }
        this.hoverBoostTimers.delete(key);
      }, boostDuration);
      this.hoverBoostTimers.set(key, timer);
    }
  },

  setupFocusTracking() {
    // Track clicks outside to unfocus
    document.addEventListener('click', (e) => {
      const clickedElement = e.target.closest('[data-sensor_id][data-attribute_id]');

      if (!clickedElement && this.focusedElements.size > 0) {
        // Clicked outside any tracked element - unfocus all
        this.focusedElements.forEach(key => {
          const [sensorId, attributeId] = key.split(':');
          this.pushEvent("unfocus", { sensor_id: sensorId, attribute_id: attributeId });
        });
        this.focusedElements.clear();
      }
    });
  },

  setupPageVisibility() {
    document.addEventListener('visibilitychange', () => {
      if (document.hidden) {
        // Page is hidden - notify server of reduced attention
        this.viewedElements.forEach(key => {
          const [sensorId, attributeId] = key.split(':');
          this.pushEvent("page_hidden", { sensor_id: sensorId, attribute_id: attributeId });
        });
      } else {
        // Page is visible again - restore attention
        this.viewedElements.forEach(key => {
          const [sensorId, attributeId] = key.split(':');
          this.pushEvent("page_visible", { sensor_id: sensorId, attribute_id: attributeId });
        });
      }
    });
  },

  setupBatteryTracking() {
    // Battery Status API - supported in Chrome, Edge, Opera
    // Falls back gracefully if not available
    if ('getBattery' in navigator) {
      navigator.getBattery().then(battery => {
        this.battery = battery;
        this.updateBatteryState();

        // Listen for battery level changes
        battery.addEventListener('levelchange', () => this.updateBatteryState());
        battery.addEventListener('chargingchange', () => this.updateBatteryState());
      }).catch(err => {
        console.debug('Battery API not available:', err);
      });
    }
  },

  updateBatteryState() {
    if (!this.battery) return;

    const level = this.battery.level;
    const charging = this.battery.charging;
    let newState = 'normal';

    // Only apply battery constraints when not charging
    if (!charging) {
      if (level < BATTERY_CRITICAL_THRESHOLD) {
        newState = 'critical';
      } else if (level < BATTERY_LOW_THRESHOLD) {
        newState = 'low';
      }
    }

    // Only push event if state changed
    if (newState !== this.batteryState) {
      const oldState = this.batteryState;
      this.batteryState = newState;

      console.debug(`Battery state changed: ${oldState} -> ${newState} (level: ${Math.round(level * 100)}%, charging: ${charging})`);

      // Notify server of battery state change
      this.pushEvent("battery_state_changed", {
        state: newState,
        level: Math.round(level * 100),
        charging: charging
      });
    }
  },

  debouncedPush(key, event, payload) {
    // Clear existing timer for this key
    if (this.debounceTimers.has(key)) {
      clearTimeout(this.debounceTimers.get(key));
    }

    // Set new debounced push
    const timer = setTimeout(() => {
      this.pushEvent(event, payload);
      this.debounceTimers.delete(key);
    }, DEBOUNCE_MS);

    this.debounceTimers.set(key, timer);
  }
};

/**
 * SensorPinControl Hook
 *
 * Handles sensor pinning for guaranteed high-frequency updates.
 */
export const SensorPinControl = {
  mounted() {
    const sensorId = this.el.dataset.sensor_id;

    this.updatePinVisual = () => {
      const isPinned = this.el.dataset.pinned === 'true';
      const icon = this.el.querySelector('svg, .heroicon');

      if (isPinned) {
        this.el.classList.add('text-orange-400');
        this.el.classList.remove('text-gray-400');
        this.el.title = 'Unpin sensor';
        if (icon) icon.setAttribute('fill', 'currentColor');
      } else {
        this.el.classList.remove('text-orange-400');
        this.el.classList.add('text-gray-400');
        this.el.title = 'Pin sensor for high-frequency updates';
        if (icon) icon.setAttribute('fill', 'none');
      }
    };

    this.el.addEventListener('click', () => {
      const isPinned = this.el.dataset.pinned === 'true';

      if (isPinned) {
        this.pushEvent("unpin_sensor", { sensor_id: sensorId });
        this.el.dataset.pinned = 'false';
      } else {
        this.pushEvent("pin_sensor", { sensor_id: sensorId });
        this.el.dataset.pinned = 'true';
      }

      this.updatePinVisual();
    });

    // Handle server-initiated pin state changes
    this.handleEvent("pin_state_changed", ({ sensor_id, pinned }) => {
      if (sensor_id === sensorId) {
        this.el.dataset.pinned = pinned ? 'true' : 'false';
        this.updatePinVisual();
      }
    });

    this.updatePinVisual();
  }
};

export default { AttentionTracker, SensorPinControl };
