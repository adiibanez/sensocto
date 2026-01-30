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

    // Initial calculation with slight delay to ensure DOM is ready
    setTimeout(() => this.calculateVisibleRange(), 0);
  },

  destroyed() {
    window.removeEventListener('scroll', this.scrollHandler);
    if (this.resizeObserver) this.resizeObserver.disconnect();
    if (this.scrollTimeout) clearTimeout(this.scrollTimeout);
    if (this.throttleTimer) clearTimeout(this.throttleTimer);
  },

  updated() {
    const newTotal = parseInt(this.el.dataset.totalSensors) || 0;
    if (newTotal !== this.totalItems) {
      this.totalItems = newTotal;
      this.calculateVisibleRange();
    }
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

    // Update if: first render, OR approaching edge of buffer, OR significant change
    const isFirstRender = this.lastStart === null;
    const approachingEdge = (startIndex < this.lastStart && startDelta >= PRELOAD_THRESHOLD * this.cols) ||
                           (endIndex > this.lastEnd && endDelta >= PRELOAD_THRESHOLD * this.cols);
    const significantChange = startDelta >= MIN_CHANGE_THRESHOLD || endDelta >= MIN_CHANGE_THRESHOLD;

    if (isFirstRender || approachingEdge || significantChange) {
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
      this.pushEvent("visible_range_changed", payload);
    } else {
      this.pendingRange = payload;
      if (!this.throttleTimer) {
        const delay = MIN_UPDATE_INTERVAL_MS - timeSinceLastPush;
        this.throttleTimer = setTimeout(() => {
          this.throttleTimer = null;
          if (this.pendingRange) {
            this.lastPushTime = Date.now();
            this.pushEvent("visible_range_changed", this.pendingRange);
            this.pendingRange = null;
          }
        }, delay);
      }
    }
  }
};
