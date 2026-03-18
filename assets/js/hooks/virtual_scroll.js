/**
 * VirtualScrollHook - Platform-adaptive infinite scroll for sensor grid
 *
 * Only renders sensors in the visible viewport + buffer, using CSS spacers
 * to maintain scroll position and total content height.
 *
 * Configuration via data attributes:
 * - data-total-sensors: Total number of sensors
 * - data-row-height: Height of each row in pixels (default: 140)
 */

const DEFAULT_ROW_HEIGHT = 140;
const BUFFER_ROWS = 8;  // Buffer rows for smooth scrolling
const PRELOAD_THRESHOLD = 3;  // Preload when within N rows of edge
const MIN_CHANGE_THRESHOLD = 12;  // Minimum sensors change to trigger update (increased for stability)
const MIN_UPDATE_INTERVAL_MS = 500;  // Minimum time between server updates to prevent crash (increased for stability)

export const VirtualScrollHook = {
  mounted() {
    this.rowHeight = parseInt(this.el.dataset.rowHeight) || DEFAULT_ROW_HEIGHT;
    this.totalItems = parseInt(this.el.dataset.totalSensors) || 0;
    this.cols = 1;
    this.scrollTimeout = null;
    this.lastStart = null;
    this.lastEnd = null;
    this.pendingUpdate = false;
    this.lastPushTime = 0;  // Track last server update time
    this.pendingRange = null;  // Store pending range during throttle
    this.throttleTimer = null;  // Timer for delayed update
    this.isLoading = false;  // Track loading state
    this.overlayEl = null;  // Floating overlay element

    this.createOverlay();
    this.detectColumns();

    // Use requestAnimationFrame for smoother scroll handling
    this.scrollHandler = () => {
      if (!this.pendingUpdate) {
        this.pendingUpdate = true;
        requestAnimationFrame(() => {
          this.calculateVisibleRange();
          this.pendingUpdate = false;
        });
      }
    };
    window.addEventListener('scroll', this.scrollHandler, { passive: true });

    this.resizeObserver = new ResizeObserver(() => {
      this.detectColumns();
      this.calculateVisibleRange();
    });
    this.resizeObserver.observe(this.el);

    // Listen for server acknowledgment that loading is complete
    this.handleEvent("virtual_scroll_loaded", () => {
      this.isLoading = false;
      this.updateLoadingIndicator();
    });

    // Initial calculation with slight delay to ensure DOM is ready
    setTimeout(() => this.calculateVisibleRange(), 0);
  },

  destroyed() {
    window.removeEventListener('scroll', this.scrollHandler);
    if (this.resizeObserver) this.resizeObserver.disconnect();
    if (this.scrollTimeout) clearTimeout(this.scrollTimeout);
    if (this.throttleTimer) clearTimeout(this.throttleTimer);
    if (this.overlayEl) this.overlayEl.remove();
  },

  updated() {
    const newTotal = parseInt(this.el.dataset.totalSensors) || 0;
    if (newTotal !== this.totalItems) {
      this.totalItems = newTotal;
      this.calculateVisibleRange();
    }
  },

  createOverlay() {
    this.overlayEl = document.createElement('div');
    this.overlayEl.style.cssText = 'position:fixed;top:50%;left:50%;transform:translate(-50%,-50%);z-index:40;pointer-events:none;opacity:0;transition:opacity 150ms ease;';
    this.overlayEl.innerHTML = `
      <div style="display:flex;flex-direction:column;align-items:center;gap:12px;background:rgba(17,24,39,0.85);backdrop-filter:blur(12px);color:#e5e7eb;padding:24px 32px;border-radius:12px;box-shadow:0 25px 50px -12px rgba(0,0,0,0.5);border:1px solid rgba(75,85,99,0.5);">
        <svg style="animation:spin 1s linear infinite;height:32px;width:32px;color:#fb923c;" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
          <circle style="opacity:0.25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
          <path style="opacity:0.75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
        </svg>
        <span style="font-size:14px;font-weight:500;">Loading sensors...</span>
      </div>`;
    document.body.appendChild(this.overlayEl);
  },

  detectColumns() {
    const style = getComputedStyle(this.el);
    const cols = style.gridTemplateColumns.split(' ').filter(c => c !== '').length;
    this.cols = Math.max(1, cols);
  },

  calculateVisibleRange() {
    const scrollTop = window.scrollY;
    const viewportHeight = window.innerHeight;
    const containerRect = this.el.getBoundingClientRect();
    const containerTop = containerRect.top + scrollTop;

    const relativeScroll = Math.max(0, scrollTop - containerTop);
    const startRow = Math.max(0, Math.floor(relativeScroll / this.rowHeight) - BUFFER_ROWS);
    const visibleRows = Math.ceil(viewportHeight / this.rowHeight) + (BUFFER_ROWS * 2);
    const totalRows = Math.ceil(this.totalItems / this.cols);
    const endRow = Math.min(startRow + visibleRows, totalRows);

    const startIndex = startRow * this.cols;
    const endIndex = Math.min(endRow * this.cols, this.totalItems);

    // Only update if range changed significantly (avoid micro-updates during smooth scroll)
    const startDelta = this.lastStart !== null ? Math.abs(startIndex - this.lastStart) : Infinity;
    const endDelta = this.lastEnd !== null ? Math.abs(endIndex - this.lastEnd) : Infinity;

    // Update if: first render, OR approaching edge of buffer, OR significant change, OR reached start/end of list
    const isFirstRender = this.lastStart === null;
    const approachingEdge = (startIndex < this.lastStart && startDelta >= PRELOAD_THRESHOLD * this.cols) ||
                           (endIndex > this.lastEnd && endDelta >= PRELOAD_THRESHOLD * this.cols);
    const significantChange = startDelta >= MIN_CHANGE_THRESHOLD || endDelta >= MIN_CHANGE_THRESHOLD;
    // Always update when we've scrolled to the very start (fixes top spacer bug)
    const reachedStart = startIndex === 0 && this.lastStart !== 0;
    // Always update when we've scrolled to include all items (fixes "1 more below" indicator bug)
    const reachedEnd = endIndex === this.totalItems && this.lastEnd !== this.totalItems;

    if (isFirstRender || approachingEdge || significantChange || reachedStart || reachedEnd) {
      this.lastStart = startIndex;
      this.lastEnd = endIndex;
      this.throttledPushRange(startIndex, endIndex);
    }
  },

  throttledPushRange(startIndex, endIndex) {
    const now = Date.now();
    const timeSinceLastPush = now - this.lastPushTime;

    const payload = {
      start_index: startIndex,
      end_index: endIndex,
      cols: this.cols
    };

    if (timeSinceLastPush >= MIN_UPDATE_INTERVAL_MS) {
      this.lastPushTime = now;
      this.pendingRange = null;
      if (this.throttleTimer) {
        clearTimeout(this.throttleTimer);
        this.throttleTimer = null;
      }
      this.isLoading = true;
      this.updateLoadingIndicator();
      this.pushEvent("visible_range_changed", payload);
      window.dispatchEvent(new CustomEvent("sensor-range-changed", {
        detail: { startIndex: startIndex, endIndex: endIndex },
      }));
    } else {
      this.pendingRange = payload;
      if (!this.throttleTimer) {
        const delay = MIN_UPDATE_INTERVAL_MS - timeSinceLastPush;
        this.throttleTimer = setTimeout(() => {
          this.throttleTimer = null;
          if (this.pendingRange) {
            this.lastPushTime = Date.now();
            this.isLoading = true;
            this.updateLoadingIndicator();
            this.pushEvent("visible_range_changed", this.pendingRange);
            window.dispatchEvent(new CustomEvent("sensor-range-changed", {
              detail: { startIndex: this.pendingRange.start_index, endIndex: this.pendingRange.end_index },
            }));
            this.pendingRange = null;
          }
        }, delay);
      }
    }
  },

  updateLoadingIndicator() {
    if (!this.overlayEl) return;

    // Position the overlay centered over the grid
    const rect = this.el.getBoundingClientRect();
    const gridVisible = rect.bottom > 0 && rect.top < window.innerHeight;

    if (this.isLoading && gridVisible) {
      const centerY = Math.max(rect.top, 0) + Math.min(rect.height, window.innerHeight - Math.max(rect.top, 0)) / 2;
      const centerX = rect.left + rect.width / 2;
      this.overlayEl.style.top = centerY + 'px';
      this.overlayEl.style.left = centerX + 'px';
      this.overlayEl.style.opacity = '1';
    } else {
      this.overlayEl.style.opacity = '0';
    }
  }
};
