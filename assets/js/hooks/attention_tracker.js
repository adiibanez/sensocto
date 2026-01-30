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
// Default ping interval - server can adjust based on system load
// Uses jitter to distribute load across clients (3-5 seconds range)
const DEFAULT_LATENCY_PING_INTERVAL_MS = 3000;
const LATENCY_PING_JITTER_MS = 2000;  // Random jitter added to interval (0 to this value)
const MIN_LATENCY_PING_INTERVAL_MS = 1000;   // Floor for high-priority sensors
const MAX_LATENCY_PING_INTERVAL_MS = 30000;  // Cap for low-priority/many sensors

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
  // Lazy initialization - ensure all state is set up
  ensureInitialized() {
    // ALWAYS update the hook instance reference on the element
    // This ensures event listeners use the CURRENT hook instance (with valid __view)
    if (this.el) {
      this.el._attentionHookInstance = this;
    }

    if (this._initialized) return;
    this._initialized = true;

    this.observers = new Map();
    this.debounceTimers = new Map();
    this.focusedElements = new Set();
    this.viewedElements = new Set();
    this.hoveredElements = new Set();
    this.hoverBoostTimers = new Map();
    this.hoverDebounceTimers = new Map();
    this.batteryState = 'normal';
    this.battery = null;

    // Determine target for pushEvent - find the closest LiveComponent container
    this.pushTarget = this.el.closest('[data-phx-component]') || this.el;

    // Set up intersection observer for visibility tracking
    this.intersectionObserver = new IntersectionObserver(
      (entries) => this.handleIntersection(entries),
      { threshold: 0.1, rootMargin: '50px' }
    );

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

    // Set up latency measurement ping/pong
    this.setupLatencyMeasurement();
  },

  mounted() {
    this._initialized = false;  // Force re-init on mount
    this.ensureInitialized();
    this.observeAttributes();
  },

  updated() {
    this.ensureInitialized();  // Ensure initialized even if mounted wasn't called
    this.observeAttributes();
  },

  destroyed() {
    // Clean up observers
    if (this.intersectionObserver) {
      this.intersectionObserver.disconnect();
    }

    // Clear latency ping interval
    if (this.latencyPingTimeout) {
      clearTimeout(this.latencyPingTimeout);
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
      this.pushEventTo(this.pushTarget,"hover_leave", { sensor_id: sensorId, attribute_id: attributeId });
    });

    // Unregister all views
    this.viewedElements.forEach(key => {
      const [sensorId, attributeId] = key.split(':');
      this.pushEventTo(this.pushTarget,"view_leave", { sensor_id: sensorId, attribute_id: attributeId });
    });

    // Unregister all focus
    this.focusedElements.forEach(key => {
      const [sensorId, attributeId] = key.split(':');
      this.pushEventTo(this.pushTarget,"unfocus", { sensor_id: sensorId, attribute_id: attributeId });
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

      // Add click and hover listeners (only once per element)
      // Listeners look up current hook instance dynamically to handle Phoenix reconnects
      if (!el._attentionClickHandler) {
        // Store reference to hook container element for lookups
        const hookEl = this.el;
        el._attentionClickHandler = () => {
          const currentHook = hookEl._attentionHookInstance;
          if (currentHook) currentHook.handleClick(el);
        };
        el._attentionMouseEnterHandler = () => {
          const currentHook = hookEl._attentionHookInstance;
          if (currentHook) currentHook.handleMouseEnter(el);
        };
        el._attentionMouseLeaveHandler = () => {
          const currentHook = hookEl._attentionHookInstance;
          if (currentHook) currentHook.handleMouseLeave(el);
        };
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

    // Only set up listeners once PER ELEMENT (listeners are reused across hook instances)
    if (this.el._attentionSensorListenerSetup) {
      // Update the hook instance reference so existing listeners use the new instance
      this.el._attentionHookInstance = this;
      return;
    }

    this.el._attentionSensorListenerSetup = true;
    this.el._attentionHookInstance = this;

    const el = this.el;

    // Track sensor-level hover using a synthetic "_sensor" attribute id
    // This enables hover attention even when mouse is over header/empty areas
    // IMPORTANT: Don't capture `this` in closure - look up current hook instance dynamically
    const mouseEnterHandler = () => {
      const currentHook = el._attentionHookInstance;
      if (currentHook) {
        currentHook.handleSensorMouseEnter(sensorId);
      }
    };
    const mouseLeaveHandler = () => {
      const currentHook = el._attentionHookInstance;
      if (currentHook) {
        currentHook.handleSensorMouseLeave(sensorId);
      }
    };

    // Store handlers on element so we can remove them later if needed
    el._sensorMouseEnterHandler = mouseEnterHandler;
    el._sensorMouseLeaveHandler = mouseLeaveHandler;

    el.addEventListener('mouseenter', mouseEnterHandler);
    el.addEventListener('mouseleave', mouseLeaveHandler);

    // Also observe the container for intersection (sensor visibility)
    if (this.intersectionObserver) {
      this.intersectionObserver.observe(el);
      this.observers.set(`${sensorId}:_sensor`, el);
    }
  },

  handleSensorMouseEnter(sensorId) {
    // Guard: element may have been removed from DOM during fast scroll
    if (!this.el || !this.el.isConnected) return;

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
        if (!el || !el.dataset) return;
        const attrKey = `${el.dataset.sensor_id}:${el.dataset.attribute_id}`;
        if (!this.hoveredElements.has(attrKey)) {
          this.pushEventTo(this.pushTarget,"hover_enter", {
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
          // Guard: element may have been removed from DOM during fast scroll
          if (this.el && this.el.isConnected) {
            // Send hover_leave for all attributes
            const elements = this.el.querySelectorAll('[data-sensor_id][data-attribute_id]');
            elements.forEach(el => {
              if (!el || !el.dataset) return;
              const attrKey = `${el.dataset.sensor_id}:${el.dataset.attribute_id}`;
              if (this.hoveredElements.has(attrKey)) {
                this.pushEventTo(this.pushTarget,"hover_leave", {
                  sensor_id: el.dataset.sensor_id,
                  attribute_id: el.dataset.attribute_id
                });
                this.hoveredElements.delete(attrKey);
              }
            });
          }
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
      // Guard: element may have been removed from DOM during fast scroll
      if (!el || !el.dataset) return;

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
            this.pushEventTo(this.pushTarget,"unfocus", { sensor_id: sensorId, attribute_id: attributeId });
            this.focusedElements.delete(key);
          }
        }
      }
    });
  },

  handleClick(el) {
    const sensorId = el.dataset.sensor_id;
    const attributeId = el.dataset.attribute_id;

    // Guard: only handle focus for elements that have both sensor_id and attribute_id
    // The container element only has sensor_id, so clicks on it should be ignored
    if (!sensorId || !attributeId) {
      return;
    }

    const key = `${sensorId}:${attributeId}`;

    if (!this.focusedElements.has(key)) {
      // Unfocus any previously focused element
      this.focusedElements.forEach(focusedKey => {
        if (focusedKey !== key) {
          const [prevSensorId, prevAttributeId] = focusedKey.split(':');
          this.pushEventTo(this.pushTarget,"unfocus", { sensor_id: prevSensorId, attribute_id: prevAttributeId });
        }
      });
      this.focusedElements.clear();

      // Focus this element
      this.pushEventTo(this.pushTarget,"focus", { sensor_id: sensorId, attribute_id: attributeId });
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
      this.pushEventTo(this.pushTarget,"view_enter", { sensor_id: sensorId, attribute_id: attributeId });
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
      this.pushEventTo(this.pushTarget,"hover_enter", { sensor_id: sensorId, attribute_id: attributeId });
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
          this.pushEventTo(this.pushTarget,"hover_leave", { sensor_id: sensorId, attribute_id: attributeId });
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
          this.pushEventTo(this.pushTarget,"unfocus", { sensor_id: sensorId, attribute_id: attributeId });
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
          this.pushEventTo(this.pushTarget,"page_hidden", { sensor_id: sensorId, attribute_id: attributeId });
        });
      } else {
        // Page is visible again - restore attention
        this.viewedElements.forEach(key => {
          const [sensorId, attributeId] = key.split(':');
          this.pushEventTo(this.pushTarget,"page_visible", { sensor_id: sensorId, attribute_id: attributeId });
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
      this.pushEventTo(this.pushTarget,"battery_state_changed", {
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
      this.pushEventTo(this.pushTarget,event, payload);
      this.debounceTimers.delete(key);
    }, DEBOUNCE_MS);

    this.debounceTimers.set(key, timer);
  },

  setupLatencyMeasurement() {
    this.pendingPingId = null;
    this.pendingPingSentAt = null;
    this.pingCounter = 0;
    this.currentPingInterval = DEFAULT_LATENCY_PING_INTERVAL_MS;

    // Listen for pong responses from server
    this.handleEvent("latency_pong", ({ ping_id, next_interval_ms }) => {
      if (this.pendingPingId !== null && ping_id === this.pendingPingId) {
        const latencyMs = Math.round(performance.now() - this.pendingPingSentAt);
        this.pendingPingId = null;
        this.pendingPingSentAt = null;

        // Report latency back to server for display
        this.pushEventTo(this.pushTarget,"latency_report", { latency_ms: latencyMs });

        // Update ping interval if server suggests a different one
        if (next_interval_ms && next_interval_ms !== this.currentPingInterval) {
          const newInterval = Math.max(MIN_LATENCY_PING_INTERVAL_MS,
                                       Math.min(MAX_LATENCY_PING_INTERVAL_MS, next_interval_ms));
          if (newInterval !== this.currentPingInterval) {
            this.currentPingInterval = newInterval;
            this.rescheduleLatencyPing();
          }
        }
      }
    });

    // Send initial ping with random delay to stagger client requests
    const initialDelay = Math.floor(Math.random() * LATENCY_PING_JITTER_MS);
    setTimeout(() => {
      this.sendLatencyPing();
      // Then ping periodically with jitter
      this.scheduleNextPing();
    }, initialDelay);
  },

  scheduleNextPing() {
    // Add random jitter to distribute load across clients
    const jitter = Math.floor(Math.random() * LATENCY_PING_JITTER_MS);
    const intervalWithJitter = this.currentPingInterval + jitter;

    this.latencyPingTimeout = setTimeout(() => {
      this.sendLatencyPing();
      this.scheduleNextPing();
    }, intervalWithJitter);
  },

  rescheduleLatencyPing() {
    if (this.latencyPingTimeout) {
      clearTimeout(this.latencyPingTimeout);
    }
    this.scheduleNextPing();
  },

  sendLatencyPing() {
    // Only send if no pending ping (avoid overlapping measurements)
    if (this.pendingPingId === null) {
      this.pingCounter++;
      this.pendingPingId = this.pingCounter;
      this.pendingPingSentAt = performance.now();
      this.pushEventTo(this.pushTarget,"latency_ping", { ping_id: this.pendingPingId });
    }
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
    // Target the closest LiveComponent container for pushEventTo
    this.pushTarget = this.el.closest('[data-phx-component]') || this.el;

    this.updatePinVisual = () => {
      // Guard: element may have been removed from DOM during fast scroll
      if (!this.el || !this.el.isConnected) return;

      const isPinned = this.el.dataset.pinned === 'true';
      const icon = this.el.querySelector('svg, .heroicon');

      if (isPinned) {
        this.el.classList.add('text-orange-400');
        this.el.classList.remove('text-gray-400');
        this.el.title = 'Unpin sensor';
        if (icon && icon.setAttribute) icon.setAttribute('fill', 'currentColor');
      } else {
        this.el.classList.remove('text-orange-400');
        this.el.classList.add('text-gray-400');
        this.el.title = 'Pin sensor for high-frequency updates';
        if (icon && icon.setAttribute) icon.setAttribute('fill', 'none');
      }
    };

    this.el.addEventListener('click', () => {
      const isPinned = this.el.dataset.pinned === 'true';

      if (isPinned) {
        this.pushEventTo(this.pushTarget,"unpin_sensor", { sensor_id: sensorId });
        this.el.dataset.pinned = 'false';
      } else {
        this.pushEventTo(this.pushTarget,"pin_sensor", { sensor_id: sensorId });
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
