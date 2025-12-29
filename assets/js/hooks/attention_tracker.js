/**
 * AttentionTracker Hook
 *
 * Tracks user attention on sensor attributes for back-pressure control.
 * Uses IntersectionObserver for viewport visibility and focus/click events
 * for active interaction detection.
 */

const DEBOUNCE_MS = 300;

export const AttentionTracker = {
  mounted() {
    this.observers = new Map();
    this.debounceTimers = new Map();
    this.focusedElements = new Set();
    this.viewedElements = new Set();

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

    // Handle dynamic updates
    this.handleEvent("attributes_updated", () => {
      this.observeAttributes();
    });
  },

  destroyed() {
    // Clean up observers
    if (this.intersectionObserver) {
      this.intersectionObserver.disconnect();
    }

    // Clear all debounce timers
    this.debounceTimers.forEach(timer => clearTimeout(timer));
    this.debounceTimers.clear();

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

      // Only observe if not already observed
      if (!this.observers.has(key)) {
        this.observers.set(key, el);
        this.intersectionObserver.observe(el);

        // Add click listener for focus
        el.addEventListener('click', () => this.handleClick(el));
        el.addEventListener('mouseenter', () => this.handleMouseEnter(el));
      }
    });
  },

  handleIntersection(entries) {
    entries.forEach(entry => {
      const el = entry.target;
      const sensorId = el.dataset.sensor_id;
      const attributeId = el.dataset.attribute_id;

      if (!sensorId || !attributeId) return;

      const key = `${sensorId}:${attributeId}`;

      if (entry.isIntersecting) {
        // Element entered viewport
        if (!this.viewedElements.has(key)) {
          this.debouncedPush(key, "view_enter", { sensor_id: sensorId, attribute_id: attributeId });
          this.viewedElements.add(key);
        }
      } else {
        // Element left viewport
        if (this.viewedElements.has(key)) {
          this.debouncedPush(key, "view_leave", { sensor_id: sensorId, attribute_id: attributeId });
          this.viewedElements.delete(key);

          // Also remove focus if was focused
          if (this.focusedElements.has(key)) {
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
    // Optionally boost attention on hover (lighter than click focus)
    // For now, just ensure it's registered as viewed
    const sensorId = el.dataset.sensor_id;
    const attributeId = el.dataset.attribute_id;
    const key = `${sensorId}:${attributeId}`;

    if (!this.viewedElements.has(key)) {
      this.pushEvent("view_enter", { sensor_id: sensorId, attribute_id: attributeId });
      this.viewedElements.add(key);
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
