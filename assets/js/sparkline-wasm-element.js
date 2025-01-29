// import init, { draw_sparkline } from '../../wasm-sparkline/pkg/sparkline.js'; // Adjust path

//import init, { draw_sparkline } from '/assets/sparkline.js';

class SensoctoSparklineWasm extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({ mode: 'open' });
        this.maxSamples = 0;
        this.timeWindow = 5;
        this.sampleRate = 20;
        this.resolution = 2;
        this.data = [];
        this.lastTime = 0;
        this.isVisible = false;

        console.log("here");
    }

    static get observedAttributes() {
        return [
            "line-color",
            "line-width",
            "smoothing",
            "time-window",
            "burst-threshold",
            "operation-mode",
            "draw-scales",
            "min-value",
            "max-value",
        ];
    }
    attributeChangedCallback(name, oldValue, newValue) {
        this.render();
    }

    async connectedCallback() {
        //await init();
        this.shadowRoot.innerHTML = `
          <canvas id="sparkline-canvas" width="200" height="300" style="margin: 0, padding: 0"></canvas>
        `;
        this.canvas = this.shadowRoot.getElementById('sparkline-canvas');
        this.ctx = this.canvas.getContext('2d');
        this.observer = new IntersectionObserver((entries) => {
            this.isVisible = entries[0].isIntersecting;
        }, { threshold: 0.1 });
        this.observer.observe(this.canvas)
        this.maxSamples = this.calculateMaxSamples(this.canvas.width, this.timeWindow, this.sampleRate, this.resolution);
        this.startRenderLoop();
    }
    calculateMaxSamples(width, timeWindow, sampleRate, resolution) {
        return width * timeWindow * sampleRate * resolution;
    }
    getParams() {
        return {
            lineColor: this.getAttribute('line-color') || 'blue',
            lineWidth: parseFloat(this.getAttribute('line-width') || 1),
            smoothing: parseInt(this.getAttribute('smoothing') || 20),
            timeWindow: parseFloat(this.getAttribute('time-window') || 5),
            burstThreshold: parseFloat(this.getAttribute('burst-threshold') || 1),
            operationMode: this.getAttribute('operation-mode') || 'absolute',
            drawScales: this.getAttribute('draw-scales') === 'true',
            minValue: this.getAttribute('min-value') ? parseFloat(this.getAttribute('min-value')) : null,
            maxValue: this.getAttribute('max-value') ? parseFloat(this.getAttribute('max-value')) : null,
        }
    }

    renderSparkline(timestamp, canvas, ctx, data, width, height, localLastTime, isVisible) {
        if (!isVisible) return localLastTime;
        if (localLastTime === 0) {
            localLastTime = window.performance.now();
            return;
        }

        const delta = timestamp - localLastTime;

        if (true || delta > 1000 / this.sampleRate) {
            localLastTime = timestamp;
            const noise = (Math.random() - 0.5) * 2;
            const currentTime = Date.now();
            const nextValue = Math.sin(currentTime / 1000) * 10 + 20 + noise;
            data.push({ timestamp: currentTime, payload: nextValue });
            if (data.length > this.maxSamples) {
                data.shift();
            }
        }
        console.log("Rendering", canvas.id, data.length);

        draw_sparkline(
            data,
            width,
            height,
            ctx,
            this.getParams().lineColor,
            this.getParams().lineWidth,
            this.getParams().smoothing,
            this.getParams().timeWindow,
            this.getParams().burstThreshold,
            this.getParams().operationMode,
            this.getParams().drawScales,
            this.getParams().minValue,
            this.getParams().maxValue,
        );
        return localLastTime;
    }

    render(timestamp) {
        if (!this.isVisible) return;

        if (this.data) {
            this.lastTime = this.renderSparkline(timestamp, this.canvas, this.ctx, this.data, this.canvas.width, this.canvas.height, this.lastTime, this.isVisible);
        }
        requestAnimationFrame(this.render.bind(this));
    }

    startRenderLoop() {
        requestAnimationFrame(this.render.bind(this));
    }


    disconnectedCallback() {
        if (this.observer) this.observer.disconnect()
    }
    updateData(newData) {
        if (newData) this.data = newData;
        this.render();
    }
}

customElements.define('sensocto-sparkline-wasm', SensoctoSparklineWasm);