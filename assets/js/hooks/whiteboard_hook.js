/**
 * WhiteboardHook - Collaborative whiteboard with pan, zoom & export
 *
 * State machine:
 * - INIT: Setting up canvas
 * - SYNCED: Following controller's drawings (can pan/zoom but not draw)
 * - USER_CONTROL: User can draw, pan, zoom
 * - ERROR: Something went wrong
 *
 * Coordinate system:
 * - Logical: 1920×1080 virtual canvas (strokes stored in this space)
 * - Screen: CSS pixels (mouse/touch events)
 * - Buffer: Canvas pixel buffer (= screen × devicePixelRatio)
 * - Viewport transform: logical → buffer via ctx.setTransform
 */

const CANVAS_W = 1920;
const CANVAS_H = 1080;
const MIN_SCALE = 0.1;
const MAX_SCALE = 5.0;
const ZOOM_FACTOR = 1.2;

const CONFIG = {
    MIN_DISTANCE: 2,
    PRESSURE_SENSITIVITY: 0.5,
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
        this.dpr = window.devicePixelRatio || 1;
        this.isDrawing = false;
        this.currentStroke = null;
        this.strokes = [];
        this.lastPoint = null;

        this.viewport = { offsetX: 0, offsetY: 0, scale: 1 };
        this.isPanning = false;
        this.panStart = null;
        this.panViewportStart = null;
        this.spaceDown = false;

        this.lastPinchDist = null;
        this.lastPinchMid = null;

        this.currentTool = this.el.dataset.tool || 'pen';
        this.strokeColor = this.el.dataset.color || '#22c55e';
        this.strokeWidth = parseInt(this.el.dataset.width) || 3;
        this.backgroundColor = '#1a1a1a';

        this.currentUserId = this.el.dataset.currentUserId;
        this.controllerUserId = this.el.dataset.controllerUserId;

        this.log('Mounted, initializing canvas');
        this.initCanvas();
        this.setupEventHandlers();
        this.setupLiveViewEvents();

        this.pushEventTo(this.el, 'request_whiteboard_sync', {});
    },

    updated() {
        this.currentTool = this.el.dataset.tool || 'pen';
        this.strokeColor = this.el.dataset.color || '#22c55e';
        this.strokeWidth = parseInt(this.el.dataset.width) || 3;
        this.controllerUserId = this.el.dataset.controllerUserId;

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
                this.canvas.style.cursor = 'grab';
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
    // Canvas Setup & Viewport
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
        this.resizeCanvas();

        this.resizeObserver = new ResizeObserver(() => this.resizeCanvas());
        this.resizeObserver.observe(this.canvas.parentElement);

        this.transition(this.canControl() ? STATES.USER_CONTROL : STATES.SYNCED);
    },

    resizeCanvas() {
        if (!this.canvas) return;

        const parent = this.canvas.parentElement;
        const rect = parent.getBoundingClientRect();
        if (rect.width === 0 || rect.height === 0) return;

        this.dpr = window.devicePixelRatio || 1;

        this.canvas.width = rect.width * this.dpr;
        this.canvas.height = rect.height * this.dpr;
        this.canvas.style.width = rect.width + 'px';
        this.canvas.style.height = rect.height + 'px';

        this.fitToView();
        this.redrawCanvas();
    },

    fitToView() {
        if (!this.canvas) return;
        const cw = this.canvas.width / this.dpr;
        const ch = this.canvas.height / this.dpr;
        const scaleX = cw / CANVAS_W;
        const scaleY = ch / CANVAS_H;
        const scale = Math.min(scaleX, scaleY);
        this.viewport = {
            scale,
            offsetX: (cw - CANVAS_W * scale) / 2,
            offsetY: (ch - CANVAS_H * scale) / 2,
        };
    },

    applyViewport() {
        this.ctx.setTransform(
            this.viewport.scale * this.dpr, 0,
            0, this.viewport.scale * this.dpr,
            this.viewport.offsetX * this.dpr,
            this.viewport.offsetY * this.dpr
        );
    },

    toLogical(screenX, screenY) {
        return {
            x: (screenX - this.viewport.offsetX) / this.viewport.scale,
            y: (screenY - this.viewport.offsetY) / this.viewport.scale,
        };
    },

    zoomTo(newScale, pivotScreenX, pivotScreenY) {
        const clamped = Math.max(MIN_SCALE, Math.min(MAX_SCALE, newScale));
        const logical = this.toLogical(pivotScreenX, pivotScreenY);
        this.viewport.scale = clamped;
        this.viewport.offsetX = pivotScreenX - logical.x * clamped;
        this.viewport.offsetY = pivotScreenY - logical.y * clamped;
        this.redrawCanvas();
    },

    // ============================================================================
    // Event Handlers
    // ============================================================================

    setupEventHandlers() {
        if (!this.canvas) return;

        this._onMouseDown = this.handleMouseDown.bind(this);
        this._onMouseMove = this.handleMouseMove.bind(this);
        this._onMouseUp = this.handleMouseUp.bind(this);
        this._onWheel = this.handleWheel.bind(this);

        this.canvas.addEventListener('mousedown', this._onMouseDown);
        this.canvas.addEventListener('mousemove', this._onMouseMove);
        this.canvas.addEventListener('mouseup', this._onMouseUp);
        this.canvas.addEventListener('mouseleave', this._onMouseUp);
        this.canvas.addEventListener('wheel', this._onWheel, { passive: false });

        this._onTouchStart = this.handleTouchStart.bind(this);
        this._onTouchMove = this.handleTouchMove.bind(this);
        this._onTouchEnd = this.handleTouchEnd.bind(this);

        this.canvas.addEventListener('touchstart', this._onTouchStart, { passive: false });
        this.canvas.addEventListener('touchmove', this._onTouchMove, { passive: false });
        this.canvas.addEventListener('touchend', this._onTouchEnd);
        this.canvas.addEventListener('touchcancel', this._onTouchEnd);

        this._onKeyDown = this.handleKeyDown.bind(this);
        this._onKeyUp = this.handleKeyUp.bind(this);
        document.addEventListener('keydown', this._onKeyDown);
        document.addEventListener('keyup', this._onKeyUp);
    },

    removeEventListeners() {
        if (this.resizeObserver) {
            this.resizeObserver.disconnect();
        }
        document.removeEventListener('keydown', this._onKeyDown);
        document.removeEventListener('keyup', this._onKeyUp);
    },

    // --- Keyboard (Space = pan mode) ---

    handleKeyDown(e) {
        if (e.code === 'Space' && !e.repeat && !this.isDrawing) {
            e.preventDefault();
            this.spaceDown = true;
            if (this.canvas) this.canvas.style.cursor = 'grab';
        }
    },

    handleKeyUp(e) {
        if (e.code === 'Space') {
            this.spaceDown = false;
            if (!this.isPanning) {
                this.updateCursor();
            }
        }
    },

    // --- Mouse ---

    handleMouseDown(e) {
        if (this.spaceDown || this.state === STATES.SYNCED) {
            this.isPanning = true;
            this.panStart = { x: e.clientX, y: e.clientY };
            this.panViewportStart = { offsetX: this.viewport.offsetX, offsetY: this.viewport.offsetY };
            if (this.canvas) this.canvas.style.cursor = 'grabbing';
            return;
        }
        this.handlePointerDown(e);
    },

    handleMouseMove(e) {
        if (this.isPanning && this.panStart) {
            const dx = e.clientX - this.panStart.x;
            const dy = e.clientY - this.panStart.y;
            this.viewport.offsetX = this.panViewportStart.offsetX + dx;
            this.viewport.offsetY = this.panViewportStart.offsetY + dy;
            this.redrawCanvas();
            return;
        }
        this.handlePointerMove(e);
    },

    handleMouseUp(_e) {
        if (this.isPanning) {
            this.isPanning = false;
            this.panStart = null;
            this.panViewportStart = null;
            if (this.canvas) {
                this.canvas.style.cursor = this.spaceDown ? 'grab' : undefined;
                if (!this.spaceDown) this.updateCursor();
            }
            return;
        }
        this.handlePointerUp(_e);
    },

    // --- Wheel (zoom toward cursor) ---

    handleWheel(e) {
        e.preventDefault();
        const rect = this.canvas.getBoundingClientRect();
        const screenX = e.clientX - rect.left;
        const screenY = e.clientY - rect.top;

        const factor = e.deltaY < 0 ? ZOOM_FACTOR : 1 / ZOOM_FACTOR;
        this.zoomTo(this.viewport.scale * factor, screenX, screenY);
    },

    // --- Touch (1-finger draw or pan, 2-finger pinch-zoom) ---

    handleTouchStart(e) {
        e.preventDefault();

        if (e.touches.length === 2) {
            this.cancelCurrentStroke();
            this.isPanning = false;
            this.lastPinchDist = this.touchDistance(e.touches[0], e.touches[1]);
            this.lastPinchMid = this.touchMidpoint(e.touches[0], e.touches[1]);
            return;
        }

        if (e.touches.length === 1) {
            if (!this.canControl() || this.state !== STATES.USER_CONTROL) {
                this.isPanning = true;
                this.panStart = { x: e.touches[0].clientX, y: e.touches[0].clientY };
                this.panViewportStart = { offsetX: this.viewport.offsetX, offsetY: this.viewport.offsetY };
            } else {
                const touch = e.touches[0];
                this.handlePointerDown({ clientX: touch.clientX, clientY: touch.clientY });
            }
        }
    },

    handleTouchMove(e) {
        e.preventDefault();

        if (e.touches.length === 2 && this.lastPinchDist != null) {
            const dist = this.touchDistance(e.touches[0], e.touches[1]);
            const mid = this.touchMidpoint(e.touches[0], e.touches[1]);
            const rect = this.canvas.getBoundingClientRect();
            const pivotX = mid.x - rect.left;
            const pivotY = mid.y - rect.top;

            const scaleFactor = dist / this.lastPinchDist;
            const newScale = Math.max(MIN_SCALE, Math.min(MAX_SCALE, this.viewport.scale * scaleFactor));

            const logical = this.toLogical(pivotX, pivotY);
            this.viewport.scale = newScale;
            const dx = mid.x - this.lastPinchMid.x;
            const dy = mid.y - this.lastPinchMid.y;
            this.viewport.offsetX = pivotX - logical.x * newScale + dx;
            this.viewport.offsetY = pivotY - logical.y * newScale + dy;

            this.redrawCanvas();
            this.lastPinchDist = dist;
            this.lastPinchMid = mid;
            return;
        }

        if (e.touches.length === 1) {
            if (this.isPanning && this.panStart) {
                const dx = e.touches[0].clientX - this.panStart.x;
                const dy = e.touches[0].clientY - this.panStart.y;
                this.viewport.offsetX = this.panViewportStart.offsetX + dx;
                this.viewport.offsetY = this.panViewportStart.offsetY + dy;
                this.redrawCanvas();
                return;
            }
            if (!this.lastPinchDist) {
                const touch = e.touches[0];
                this.handlePointerMove({ clientX: touch.clientX, clientY: touch.clientY });
            }
        }
    },

    handleTouchEnd(e) {
        if (this.lastPinchDist != null) {
            this.lastPinchDist = null;
            this.lastPinchMid = null;
            return;
        }

        if (this.isPanning) {
            this.isPanning = false;
            this.panStart = null;
            this.panViewportStart = null;
            this.updateCursor();
            return;
        }

        if (e.changedTouches && e.changedTouches.length > 0) {
            const touch = e.changedTouches[0];
            this.handlePointerUp({ clientX: touch.clientX, clientY: touch.clientY });
        } else {
            this.handlePointerUp({ clientX: 0, clientY: 0 });
        }
    },

    touchDistance(t1, t2) {
        const dx = t2.clientX - t1.clientX;
        const dy = t2.clientY - t1.clientY;
        return Math.sqrt(dx * dx + dy * dy);
    },

    touchMidpoint(t1, t2) {
        return {
            x: (t1.clientX + t2.clientX) / 2,
            y: (t1.clientY + t2.clientY) / 2,
        };
    },

    cancelCurrentStroke() {
        if (this.isDrawing) {
            this.isDrawing = false;
            this.currentStroke = null;
            this.lastPoint = null;
            this.redrawCanvas();
        }
    },

    // --- Drawing pointer events (operate in logical coords) ---

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

        if (this.currentTool !== 'line' && this.currentTool !== 'rect') {
            this.applyViewport();
            this.ctx.beginPath();
            this.ctx.moveTo(point.x, point.y);
        }
    },

    handlePointerMove(e) {
        if (!this.isDrawing || !this.currentStroke) return;

        const point = this.getCanvasPoint(e);

        if (this.currentTool === 'pen' || this.currentTool === 'eraser') {
            const dist = this.distance(this.lastPoint, point);
            if (dist >= CONFIG.MIN_DISTANCE) {
                this.currentStroke.points.push(point);
                this.applyViewport();
                this.drawLine(this.lastPoint, point, this.currentStroke.color, this.currentStroke.width);
                this.sendStrokeProgress();
                this.lastPoint = point;
            }
        } else if (this.currentTool === 'line' || this.currentTool === 'rect') {
            this.redrawCanvas();
            this.applyViewport();
            this.drawShapePreview(this.currentStroke.points[0], point);
            this.currentStroke.points[1] = point;
            this.sendStrokeProgress();
        }
    },

    sendStrokeProgress() {
        if (!this.currentStroke) return;
        const now = Date.now();
        if (this._lastProgressSent && (now - this._lastProgressSent) < 50) {
            return;
        }
        this._lastProgressSent = now;
        this.pushEventTo(this.el, 'stroke_progress', { stroke: this.currentStroke });
    },

    handlePointerUp(e) {
        if (!this.isDrawing || !this.currentStroke) {
            this.isDrawing = false;
            return;
        }

        if (this.currentTool === 'line' || this.currentTool === 'rect') {
            const point = this.getCanvasPoint(e);
            this.currentStroke.points[1] = point;
        }

        if (this.currentStroke.points.length >= 1) {
            this.pushEventTo(this.el, 'stroke_complete', { stroke: this.currentStroke });
        }

        this.isDrawing = false;
        this.currentStroke = null;
        this.lastPoint = null;
    },

    // ============================================================================
    // LiveView Events
    // ============================================================================

    setupLiveViewEvents() {
        this.handleEvent('whiteboard_sync', ({ strokes, background_color }) => {
            this.log('Received whiteboard sync', { strokeCount: strokes?.length, background_color });
            this.strokes = strokes || [];
            this.backgroundColor = background_color || '#1a1a1a';
            this.redrawCanvas();
        });

        this.handleEvent('whiteboard_strokes_batch', ({ strokes }) => {
            this.log('Received stroke batch', { count: strokes?.length });
            if (strokes && strokes.length > 0) {
                this.applyViewport();
                for (const stroke of strokes) {
                    this.strokes.push(stroke);
                    this.drawStroke(stroke);
                }
            }
        });

        this.handleEvent('whiteboard_stroke_added', ({ stroke }) => {
            this.log('Received stroke', stroke);
            this.strokes.push(stroke);
            this.applyViewport();
            this.drawStroke(stroke);
        });

        this.handleEvent('whiteboard_cleared', () => {
            this.log('Canvas cleared');
            this.strokes = [];
            this.redrawCanvas();
        });

        this.handleEvent('whiteboard_undo', ({ removed_stroke }) => {
            this.log('Undo stroke', removed_stroke);
            this.strokes.pop();
            this.redrawCanvas();
        });

        this.handleEvent('whiteboard_background_changed', ({ color }) => {
            this.log('Background changed to', color);
            this.backgroundColor = color;
            this.redrawCanvas();
        });

        this.handleEvent('whiteboard_stroke_progress', ({ stroke, user_id }) => {
            if (user_id !== this.currentUserId) {
                this.redrawCanvas();
                this.applyViewport();
                this.drawStroke(stroke);
            }
        });

        this.handleEvent('whiteboard_zoom_in', () => {
            const cw = this.canvas.width / this.dpr;
            const ch = this.canvas.height / this.dpr;
            this.zoomTo(this.viewport.scale * ZOOM_FACTOR, cw / 2, ch / 2);
        });

        this.handleEvent('whiteboard_zoom_out', () => {
            const cw = this.canvas.width / this.dpr;
            const ch = this.canvas.height / this.dpr;
            this.zoomTo(this.viewport.scale / ZOOM_FACTOR, cw / 2, ch / 2);
        });

        this.handleEvent('whiteboard_fit_view', () => {
            this.fitToView();
            this.redrawCanvas();
        });

        this.handleEvent('whiteboard_export', ({ format, scale }) => {
            this.exportImage(format || 'png', scale || 1);
        });
    },

    // ============================================================================
    // Drawing Functions
    // ============================================================================

    clearCanvas() {
        if (!this.ctx || !this.canvas) return;
        this.ctx.setTransform(1, 0, 0, 1, 0, 0);
        this.ctx.fillStyle = this.backgroundColor;
        this.ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);
    },

    redrawCanvas() {
        this.clearCanvas();
        this.applyViewport();
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

        this.ctx.globalAlpha = 0.6;

        if (this.currentTool === 'line') {
            this.drawLine(start, end, color, width);
        } else if (this.currentTool === 'rect') {
            this.drawRect(start, end, color, width);
        }

        this.ctx.globalAlpha = 1.0;
    },

    // ============================================================================
    // Export
    // ============================================================================

    exportImage(format, exportScale) {
        const offscreen = document.createElement('canvas');
        offscreen.width = CANVAS_W * exportScale;
        offscreen.height = CANVAS_H * exportScale;
        const offCtx = offscreen.getContext('2d');

        offCtx.fillStyle = this.backgroundColor;
        offCtx.fillRect(0, 0, offscreen.width, offscreen.height);

        offCtx.setTransform(exportScale, 0, 0, exportScale, 0, 0);

        for (const stroke of this.strokes) {
            this.drawStrokeOn(offCtx, stroke);
        }

        const mimeType = format === 'jpg' ? 'image/jpeg' : 'image/png';
        const ext = format === 'jpg' ? 'jpg' : 'png';
        const quality = format === 'jpg' ? 0.92 : undefined;

        offscreen.toBlob((blob) => {
            if (!blob) return;
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = `whiteboard-${Date.now()}.${ext}`;
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            URL.revokeObjectURL(url);
        }, mimeType, quality);
    },

    drawStrokeOn(ctx, stroke) {
        if (!stroke || !stroke.points || stroke.points.length === 0) return;
        const { type, points, color, width } = stroke;

        if (type === 'line' && points.length >= 2) {
            ctx.strokeStyle = color;
            ctx.lineWidth = width;
            ctx.lineCap = 'round';
            ctx.beginPath();
            ctx.moveTo(points[0].x, points[0].y);
            ctx.lineTo(points[points.length - 1].x, points[points.length - 1].y);
            ctx.stroke();
        } else if (type === 'rect' && points.length >= 2) {
            ctx.strokeStyle = color;
            ctx.lineWidth = width;
            ctx.lineCap = 'square';
            ctx.lineJoin = 'miter';
            const x = Math.min(points[0].x, points[points.length - 1].x);
            const y = Math.min(points[0].y, points[points.length - 1].y);
            const w = Math.abs(points[points.length - 1].x - points[0].x);
            const h = Math.abs(points[points.length - 1].y - points[0].y);
            ctx.strokeRect(x, y, w, h);
        } else if ((type === 'pen' || type === 'eraser' || type === 'freehand') && points.length >= 1) {
            if (points.length < 2) {
                ctx.fillStyle = color;
                ctx.beginPath();
                ctx.arc(points[0].x, points[0].y, width / 2, 0, Math.PI * 2);
                ctx.fill();
            } else {
                ctx.strokeStyle = color;
                ctx.lineWidth = width;
                ctx.lineCap = 'round';
                ctx.lineJoin = 'round';
                ctx.beginPath();
                ctx.moveTo(points[0].x, points[0].y);
                for (let i = 1; i < points.length; i++) {
                    ctx.lineTo(points[i].x, points[i].y);
                }
                ctx.stroke();
            }
        }
    },

    // ============================================================================
    // Utility Functions
    // ============================================================================

    getCanvasPoint(e) {
        const rect = this.canvas.getBoundingClientRect();
        const screenX = e.clientX - rect.left;
        const screenY = e.clientY - rect.top;
        return this.toLogical(screenX, screenY);
    },

    distance(p1, p2) {
        const dx = p2.x - p1.x;
        const dy = p2.y - p1.y;
        return Math.sqrt(dx * dx + dy * dy);
    },

    canControl() {
        return !this.controllerUserId || this.controllerUserId === this.currentUserId;
    },

    updateCursor() {
        if (!this.canvas) return;
        if (this.spaceDown) {
            this.canvas.style.cursor = 'grab';
            return;
        }
        if (this.state === STATES.SYNCED) {
            this.canvas.style.cursor = 'grab';
            return;
        }
        switch (this.currentTool) {
            case 'pen':
            case 'line':
            case 'rect':
                this.canvas.style.cursor = 'crosshair';
                break;
            case 'eraser':
                this.canvas.style.cursor = 'cell';
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
