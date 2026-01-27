/**
 * WhiteboardHook - Collaborative whiteboard drawing with real-time sync
 *
 * State machine approach:
 * - INIT: Setting up canvas and context
 * - READY: Canvas ready, waiting for user interaction
 * - SYNCED: Following controller's drawings
 * - USER_CONTROL: User has control and can draw
 * - ERROR: Something went wrong
 */

const CONFIG = {
    // Drawing settings
    MIN_DISTANCE: 2,  // Minimum distance between points when drawing
    PRESSURE_SENSITIVITY: 0.5,

    // Eraser settings
    ERASER_SIZE_MULTIPLIER: 3,
};

const STATES = {
    INIT: 'INIT',
    READY: 'READY',
    SYNCED: 'SYNCED',
    USER_CONTROL: 'USER_CONTROL',
    ERROR: 'ERROR',
};

const WhiteboardHook = {
    mounted() {
        this.state = STATES.INIT;
        this.canvas = null;
        this.ctx = null;
        this.isDrawing = false;
        this.currentStroke = null;
        this.strokes = [];
        this.lastPoint = null;

        // Tool settings from data attributes
        this.currentTool = this.el.dataset.tool || 'pen';
        this.strokeColor = this.el.dataset.color || '#22c55e';
        this.strokeWidth = parseInt(this.el.dataset.width) || 3;
        this.backgroundColor = '#1a1a1a';

        // User info
        this.currentUserId = this.el.dataset.currentUserId;
        this.controllerUserId = this.el.dataset.controllerUserId;

        this.log('Mounted, initializing canvas');
        this.initCanvas();
        this.setupEventHandlers();
        this.setupLiveViewEvents();

        // Request initial sync (use pushEventTo to target the LiveComponent)
        this.pushEventTo(this.el, 'request_whiteboard_sync', {});
    },

    updated() {
        // Update tool settings from data attributes
        this.currentTool = this.el.dataset.tool || 'pen';
        this.strokeColor = this.el.dataset.color || '#22c55e';
        this.strokeWidth = parseInt(this.el.dataset.width) || 3;
        this.controllerUserId = this.el.dataset.controllerUserId;

        // Transition state based on control
        if (this.canControl()) {
            if (this.state !== STATES.USER_CONTROL) {
                this.transition(STATES.USER_CONTROL);
            }
        } else {
            if (this.state === STATES.USER_CONTROL) {
                this.transition(STATES.SYNCED);
            }
        }
    },

    destroyed() {
        this.log('Destroyed, cleaning up');
        this.removeEventListeners();
    },

    // ============================================================================
    // State Machine
    // ============================================================================

    transition(newState) {
        const oldState = this.state;
        this.state = newState;
        this.log(`State transition: ${oldState} -> ${newState}`);
        this.onStateEnter(newState);
    },

    onStateEnter(state) {
        switch (state) {
            case STATES.READY:
                this.canvas.style.cursor = 'default';
                break;
            case STATES.SYNCED:
                this.canvas.style.cursor = 'not-allowed';
                break;
            case STATES.USER_CONTROL:
                this.updateCursor();
                break;
            case STATES.ERROR:
                this.canvas.style.cursor = 'not-allowed';
                break;
        }
    },

    // ============================================================================
    // Canvas Setup
    // ============================================================================

    initCanvas() {
        const roomId = this.el.dataset.roomId;
        this.canvas = this.el.querySelector(`#whiteboard-canvas-${roomId}`);

        if (!this.canvas) {
            this.log('Canvas not found, retrying...');
            setTimeout(() => this.initCanvas(), 100);
            return;
        }

        this.ctx = this.canvas.getContext('2d');

        // Set canvas size to match container
        this.resizeCanvas();

        // Handle resize
        this.resizeObserver = new ResizeObserver(() => this.resizeCanvas());
        this.resizeObserver.observe(this.canvas.parentElement);

        this.transition(this.canControl() ? STATES.USER_CONTROL : STATES.SYNCED);
    },

    resizeCanvas() {
        if (!this.canvas) return;

        const parent = this.canvas.parentElement;
        const rect = parent.getBoundingClientRect();

        // Store current content
        const imageData = this.canvas.width > 0 && this.canvas.height > 0
            ? this.ctx.getImageData(0, 0, this.canvas.width, this.canvas.height)
            : null;

        // Resize
        this.canvas.width = rect.width;
        this.canvas.height = rect.height;

        // Redraw all strokes
        this.redrawCanvas();
    },

    // ============================================================================
    // Event Handlers
    // ============================================================================

    setupEventHandlers() {
        if (!this.canvas) return;

        // Mouse events
        this.canvas.addEventListener('mousedown', this.handlePointerDown.bind(this));
        this.canvas.addEventListener('mousemove', this.handlePointerMove.bind(this));
        this.canvas.addEventListener('mouseup', this.handlePointerUp.bind(this));
        this.canvas.addEventListener('mouseleave', this.handlePointerUp.bind(this));

        // Touch events
        this.canvas.addEventListener('touchstart', this.handleTouchStart.bind(this), { passive: false });
        this.canvas.addEventListener('touchmove', this.handleTouchMove.bind(this), { passive: false });
        this.canvas.addEventListener('touchend', this.handleTouchEnd.bind(this));
        this.canvas.addEventListener('touchcancel', this.handleTouchEnd.bind(this));
    },

    removeEventListeners() {
        if (this.resizeObserver) {
            this.resizeObserver.disconnect();
        }
    },

    handlePointerDown(e) {
        if (!this.canControl() || this.state !== STATES.USER_CONTROL) {
            return;
        }

        this.isDrawing = true;
        const point = this.getCanvasPoint(e);
        this.lastPoint = point;

        this.currentStroke = {
            type: this.currentTool,
            points: [point],
            color: this.currentTool === 'eraser' ? this.backgroundColor : this.strokeColor,
            width: this.currentTool === 'eraser' ? this.strokeWidth * CONFIG.ERASER_SIZE_MULTIPLIER : this.strokeWidth,
        };

        // For shapes, we just store start point
        if (this.currentTool === 'line' || this.currentTool === 'rect') {
            // Nothing more to do yet
        } else {
            // Start drawing immediately for freehand/eraser
            this.ctx.beginPath();
            this.ctx.moveTo(point.x, point.y);
        }
    },

    handlePointerMove(e) {
        if (!this.isDrawing || !this.currentStroke) return;

        const point = this.getCanvasPoint(e);

        if (this.currentTool === 'pen' || this.currentTool === 'eraser') {
            // Only add point if moved enough distance
            const dist = this.distance(this.lastPoint, point);
            if (dist >= CONFIG.MIN_DISTANCE) {
                this.currentStroke.points.push(point);
                this.drawLine(this.lastPoint, point, this.currentStroke.color, this.currentStroke.width);
                this.lastPoint = point;
            }
        } else if (this.currentTool === 'line' || this.currentTool === 'rect') {
            // Redraw canvas and show preview
            this.redrawCanvas();
            this.drawShapePreview(this.currentStroke.points[0], point);
        }
    },

    handlePointerUp(e) {
        if (!this.isDrawing || !this.currentStroke) {
            this.isDrawing = false;
            return;
        }

        // For shapes, add the end point
        if (this.currentTool === 'line' || this.currentTool === 'rect') {
            const point = this.getCanvasPoint(e);
            this.currentStroke.points.push(point);
        }

        // Only send stroke if it has meaningful content
        if (this.currentStroke.points.length >= 1) {
            // Use pushEventTo to target the LiveComponent (phx-target on hook element)
            this.pushEventTo(this.el, 'stroke_complete', { stroke: this.currentStroke });
        }

        this.isDrawing = false;
        this.currentStroke = null;
        this.lastPoint = null;
    },

    handleTouchStart(e) {
        e.preventDefault();
        if (e.touches.length === 1) {
            const touch = e.touches[0];
            this.handlePointerDown({ clientX: touch.clientX, clientY: touch.clientY });
        }
    },

    handleTouchMove(e) {
        e.preventDefault();
        if (e.touches.length === 1) {
            const touch = e.touches[0];
            this.handlePointerMove({ clientX: touch.clientX, clientY: touch.clientY });
        }
    },

    handleTouchEnd(e) {
        if (e.changedTouches.length > 0) {
            const touch = e.changedTouches[0];
            this.handlePointerUp({ clientX: touch.clientX, clientY: touch.clientY });
        } else {
            this.handlePointerUp({ clientX: this.lastPoint?.x || 0, clientY: this.lastPoint?.y || 0 });
        }
    },

    // ============================================================================
    // LiveView Events
    // ============================================================================

    setupLiveViewEvents() {
        // Full sync (on connect or request)
        this.handleEvent('whiteboard_sync', ({ strokes, background_color }) => {
            this.log('Received whiteboard sync', { strokeCount: strokes?.length, background_color });
            this.strokes = strokes || [];
            this.backgroundColor = background_color || '#1a1a1a';
            this.redrawCanvas();
        });

        // Batched strokes (scalability optimization)
        this.handleEvent('whiteboard_strokes_batch', ({ strokes }) => {
            this.log('Received stroke batch', { count: strokes?.length });
            if (strokes && strokes.length > 0) {
                for (const stroke of strokes) {
                    this.strokes.push(stroke);
                    this.drawStroke(stroke);
                }
            }
        });

        // Single stroke added
        this.handleEvent('whiteboard_stroke_added', ({ stroke }) => {
            this.log('Received stroke', stroke);
            this.strokes.push(stroke);
            this.drawStroke(stroke);
        });

        // Canvas cleared
        this.handleEvent('whiteboard_cleared', () => {
            this.log('Canvas cleared');
            this.strokes = [];
            this.clearCanvas();
        });

        // Undo
        this.handleEvent('whiteboard_undo', ({ removed_stroke }) => {
            this.log('Undo stroke', removed_stroke);
            this.strokes.pop();
            this.redrawCanvas();
        });

        // Background changed
        this.handleEvent('whiteboard_background_changed', ({ color }) => {
            this.log('Background changed to', color);
            this.backgroundColor = color;
            this.redrawCanvas();
        });
    },

    // ============================================================================
    // Drawing Functions
    // ============================================================================

    clearCanvas() {
        if (!this.ctx || !this.canvas) return;
        this.ctx.fillStyle = this.backgroundColor;
        this.ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);
    },

    redrawCanvas() {
        this.clearCanvas();
        for (const stroke of this.strokes) {
            this.drawStroke(stroke);
        }
    },

    drawStroke(stroke) {
        if (!stroke || !stroke.points || stroke.points.length === 0) return;

        const { type, points, color, width } = stroke;

        if (type === 'line' && points.length >= 2) {
            this.drawLine(points[0], points[points.length - 1], color, width);
        } else if (type === 'rect' && points.length >= 2) {
            this.drawRect(points[0], points[points.length - 1], color, width);
        } else if ((type === 'pen' || type === 'eraser' || type === 'freehand') && points.length >= 1) {
            this.drawFreehand(points, color, width);
        }
    },

    drawFreehand(points, color, width) {
        if (points.length < 2) {
            // Single point - draw a dot
            this.ctx.fillStyle = color;
            this.ctx.beginPath();
            this.ctx.arc(points[0].x, points[0].y, width / 2, 0, Math.PI * 2);
            this.ctx.fill();
            return;
        }

        this.ctx.strokeStyle = color;
        this.ctx.lineWidth = width;
        this.ctx.lineCap = 'round';
        this.ctx.lineJoin = 'round';

        this.ctx.beginPath();
        this.ctx.moveTo(points[0].x, points[0].y);

        for (let i = 1; i < points.length; i++) {
            this.ctx.lineTo(points[i].x, points[i].y);
        }

        this.ctx.stroke();
    },

    drawLine(start, end, color, width) {
        this.ctx.strokeStyle = color;
        this.ctx.lineWidth = width;
        this.ctx.lineCap = 'round';

        this.ctx.beginPath();
        this.ctx.moveTo(start.x, start.y);
        this.ctx.lineTo(end.x, end.y);
        this.ctx.stroke();
    },

    drawRect(start, end, color, width) {
        this.ctx.strokeStyle = color;
        this.ctx.lineWidth = width;
        this.ctx.lineCap = 'square';
        this.ctx.lineJoin = 'miter';

        const x = Math.min(start.x, end.x);
        const y = Math.min(start.y, end.y);
        const w = Math.abs(end.x - start.x);
        const h = Math.abs(end.y - start.y);

        this.ctx.strokeRect(x, y, w, h);
    },

    drawShapePreview(start, end) {
        const color = this.strokeColor;
        const width = this.strokeWidth;

        // Set preview style (slightly transparent)
        this.ctx.globalAlpha = 0.6;

        if (this.currentTool === 'line') {
            this.drawLine(start, end, color, width);
        } else if (this.currentTool === 'rect') {
            this.drawRect(start, end, color, width);
        }

        this.ctx.globalAlpha = 1.0;
    },

    // ============================================================================
    // Utility Functions
    // ============================================================================

    getCanvasPoint(e) {
        const rect = this.canvas.getBoundingClientRect();
        return {
            x: e.clientX - rect.left,
            y: e.clientY - rect.top,
        };
    },

    distance(p1, p2) {
        const dx = p2.x - p1.x;
        const dy = p2.y - p1.y;
        return Math.sqrt(dx * dx + dy * dy);
    },

    canControl() {
        // Can control if no controller is set, or if current user is the controller
        return !this.controllerUserId || this.controllerUserId === this.currentUserId;
    },

    updateCursor() {
        if (!this.canvas) return;

        switch (this.currentTool) {
            case 'pen':
                this.canvas.style.cursor = 'crosshair';
                break;
            case 'eraser':
                this.canvas.style.cursor = 'cell';
                break;
            case 'line':
            case 'rect':
                this.canvas.style.cursor = 'crosshair';
                break;
            default:
                this.canvas.style.cursor = 'crosshair';
        }
    },

    log(...args) {
        console.log('[WhiteboardHook]', ...args);
    },
};

export default WhiteboardHook;
