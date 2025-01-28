import init, { draw_sparkline } from './pkg/sparkline.js'; // Adjust path

async function run() {
    await init();

    const canvas = document.getElementById('sparkline-canvas');
    const ctx = canvas.getContext('2d');

    let width = canvas.width;
    let height = canvas.height;
    
    let maxSamples = 0;

    let timeWindow = 5;  // 5 seconds of data
    let sampleRate = 20; // 20 samples per second
    let resolution = 2; // 2 sample points for each pixel
    
    const calculateMaxSamples = (width, timeWindow, sampleRate, resolution) => {
      return width * timeWindow * sampleRate * resolution;
    }
    
    maxSamples = calculateMaxSamples(width, timeWindow, sampleRate, resolution);

    let data = [];
    let lastTime = 0;

     function render(timestamp) {
          if (lastTime === 0 ) {
            lastTime = timestamp;
            requestAnimationFrame(render);
             return
          }
          const delta = timestamp - lastTime;

        // Simulate real-time data
          if (delta > 10 / sampleRate) {
            lastTime = timestamp;
            const noise = (Math.random() - 0.5) * 2;
             const nextValue = Math.sin(timestamp/1000) * 10 + 20 + noise;
            data.push(nextValue);
            if (data.length > maxSamples) {
                 data.shift();
            }
          }

        draw_sparkline(data, width, height, ctx);
          requestAnimationFrame(render);

      }
      
      
      
    resizeCanvas();
    
    requestAnimationFrame(render);
    
        
     function resizeCanvas() {
       canvas.width = width = window.innerWidth;
       canvas.height = height = window.innerHeight;
       
       maxSamples = calculateMaxSamples(width, timeWindow, sampleRate, resolution);
       console.log("maxSamples", maxSamples);
                
       /**
        * Your drawings need to be inside this function otherwise they will be reset when 
        * you resize the browser window and the canvas goes will be cleared.
        */
     }
     
     window.addEventListener('resize', resizeCanvas, false);
  
}

run();