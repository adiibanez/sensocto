import init, { draw_sparkline } from './pkg/sparkline.js'; // Adjust path

async function run() {
  await init();

  let maxSamples = 0;

  let timeWindow = 5;  // 5 seconds of data
  let sampleRate = 20; // 20 samples per second
  let resolution = 2; // 2 sample points for each pixel

  const lineColorInput = document.getElementById('lineColorInput');
  const lineWidthInput = document.getElementById('lineWidthInput');
  const smoothingInput = document.getElementById('smoothingInput');
  const timeWindowInput = document.getElementById('timeWindowInput');
  const burstThresholdInput = document.getElementById('burstThresholdInput');
  const operationModeInput = document.getElementById('operationModeInput');
  const drawScalesInput = document.getElementById('drawScalesInput');
  const minValueInput = document.getElementById('minValueInput');
  const maxValueInput = document.getElementById('maxValueInput');

  const numSparklinesInput = document.getElementById('numSparklinesInput');
  const generateButton = document.getElementById('generateButton');
  const sparklineContainer = document.getElementById('sparklineContainer');

  const calculateMaxSamples = (width, timeWindow, sampleRate, resolution) => {
    return width * timeWindow * sampleRate * resolution;
  }

  maxSamples = calculateMaxSamples(window.innerWidth, timeWindow, sampleRate, resolution);

  let data = [];
  let lastTime = 0;
  let sparklineInstances = [];


  function getParams() {
    const params = {
      lineColor: lineColorInput.value,
      lineWidth: parseFloat(lineWidthInput.value),
      smoothing: parseInt(smoothingInput.value),
      timeWindow: parseFloat(timeWindowInput.value),
      burstThreshold: parseFloat(burstThresholdInput.value),
      operationMode: operationModeInput.value,
      drawScales: drawScalesInput.checked,
      minValue: minValueInput.value ? parseFloat(minValueInput.value) : null,
      maxValue: maxValueInput.value ? parseFloat(maxValueInput.value) : null,
    }
    //console.log("Params:", params)
    return params
  }


  function renderSparkline(timestamp, canvas, ctx, data, width, height, localLastTime) {


    if (localLastTime === 0) {
      localLastTime = window.performance.now();
      return
    }

    const delta = timestamp - localLastTime;

    // Simulate real-time data
    if (true || delta > 1000 / sampleRate) {
      localLastTime = timestamp;
      const noise = (Math.random() - 0.5) * 2;
      const currentTime = Date.now();  // Renamed variable
      const nextValue = Math.sin(currentTime / 1000) * 10 + 20 + noise;
      data.push({ timestamp: currentTime, payload: nextValue }); // Use currentTime
      if (data.length > maxSamples) {
        data.shift();
      }
    }
    console.log("Rendering", canvas.id, data.length);

    draw_sparkline(
      data,
      width,
      height,
      ctx,
      getParams().lineColor,
      getParams().lineWidth,
      getParams().smoothing,
      getParams().timeWindow,
      getParams().burstThreshold,
      getParams().operationMode,
      getParams().drawScales,
      getParams().minValue,
      getParams().maxValue,
    );
    return localLastTime;
  }


  function render(timestamp) {
    const startTime = performance.now();

    for (const instance of sparklineInstances) {
      instance.lastTime = renderSparkline(timestamp, instance.canvas, instance.ctx, instance.data, instance.width, instance.height, instance.lastTime);
    }

    const endTime = performance.now();
    const duration = endTime - startTime;

    console.log(`Rendered ${sparklineInstances.length} sparklines in ${duration.toFixed(2)}ms`);

    requestAnimationFrame(render);
  }
  function generateSparklines() {
    // Clear old instances
    sparklineContainer.innerHTML = '';
    sparklineInstances = [];

    const numSparklines = parseInt(numSparklinesInput.value);
    for (let i = 0; i < numSparklines; i++) {
      let newCanvas = document.createElement('canvas');
      newCanvas.id = `sparkline-canvas-${i}`;
      newCanvas.width = window.innerWidth;
      newCanvas.height = 50;
      newCanvas.style = 'margin: 0px; display:block; border: 1px solid black; background-color: green';
      newCanvas.classList.add("resizeable")
      sparklineContainer.appendChild(newCanvas);
      let newCtx = newCanvas.getContext('2d');

      sparklineInstances.push({
        canvas: newCanvas,
        ctx: newCtx,
        data: [],
        lastTime: 0,
        width: window.innerWidth,
        height: 50
      });
    }
    requestAnimationFrame(render);
  }

  generateButton.addEventListener('click', generateSparklines);


  resizeCanvas();

  window.addEventListener('resize', resizeCanvas, false);

  function resizeCanvas() {
    if (!sparklineInstances) return;
    for (const instance of sparklineInstances) {
      instance.canvas.width = window.innerWidth;
    }
    maxSamples = calculateMaxSamples(window.innerWidth, timeWindow, sampleRate, resolution);
  }
}
run();