import init, { draw_sparkline } from './pkg/sparkline.js'; // Adjust path

async function run() {
  await init();

  const canvas = document.getElementById('sparkline-canvas');
  const ctx = canvas.getContext('2d');

  console.log("Canvas", canvas, ctx);

  let width = canvas.width;
  let height = canvas.height;

  let maxSamples = 0;

  let timeWindow = 5;  // 5 seconds of data
  let sampleRate = 20; // 20 samples per second
  let resolution = 2; // 2 sample points for each pixel
  let timestamp = 0;

  const lineColorInput = document.getElementById('lineColorInput');
  const lineWidthInput = document.getElementById('lineWidthInput');
  const smoothingInput = document.getElementById('smoothingInput');
  const timeWindowInput = document.getElementById('timeWindowInput');
  const burstThresholdInput = document.getElementById('burstThresholdInput');
  const operationModeInput = document.getElementById('operationModeInput');
  const drawScalesInput = document.getElementById('drawScalesInput');
  const minValueInput = document.getElementById('minValueInput');
  const maxValueInput = document.getElementById('maxValueInput');

  const calculateMaxSamples = (width, timeWindow, sampleRate, resolution) => {
    return width * timeWindow * sampleRate * resolution;
  }

  maxSamples = calculateMaxSamples(width, timeWindow, sampleRate, resolution);

  let data = [];
  let lastTime = 0;
  let isVisible = false;

  const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      isVisible = entry.isIntersecting;
      if (isVisible) {
        requestAnimationFrame(render);
      }
    });
  }, { threshold: 0.1 });

  observer.observe(canvas);

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
    console.log("Params:", params)
    return params
  }

  function render() {

    if (!isVisible) return;

    if (lastTime === 0) {
      lastTime = Date.now();
      requestAnimationFrame(render);
      return
    }

    console.log('here');
    const delta = timestamp - lastTime;

    // Simulate real-time data
    if (delta > 1000 / sampleRate) {
      lastTime = timestamp;
      const noise = (Math.random() - 0.5) * 2;
      const timestamp = Date.now();
      const nextValue = Math.sin(timestamp / 1000) * 10 + 20 + noise;
      data.push({ timestamp: timestamp, payload: nextValue });
      if (data.length > maxSamples) {
        data.shift();
      }
    }

    console.log(data.length, data);


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


    requestAnimationFrame(render);

  }


  function resizeCanvas() {
    return;
    canvas.width = width = window.innerWidth;
    //canvas.height = height = (window.innerHeight - 1000);

    maxSamples = calculateMaxSamples(width, timeWindow, sampleRate, resolution);
  }

  resizeCanvas();
  requestAnimationFrame(render);

  window.addEventListener('resize', resizeCanvas, false);


}

run();