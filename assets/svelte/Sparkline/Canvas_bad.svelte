<script>
    export let width = 100;
    export let height = 50;
    export let color = "#ffc107";
    export let lineWidth = 2;
    export let points = [];
    export let id = "canvasLayer";

    let canvas;
    let ctx;

   $: if (canvas && points) {
        console.log("CanvasLayer: canvas and points are available, will draw", id);
        ctx = canvas.getContext("2d");
        drawCanvas();
    }


   function drawCanvas() {
      if (!ctx || !points?.length) {
            console.log("CanvasLayer: No context or points to draw, skipping draw...", id);
            return; // Exit immediately if canvas context or data is invalid.
        }

       console.log("CanvasLayer: Drawing the line using given points", id, points);
        ctx.clearRect(0, 0, width, height);  // Always clear canvas
       ctx.lineWidth = lineWidth; // Set line width.
       let prevX = null;
       let prevY = null;



        for (let i = 0; i < points.length; i++) {
           const point = points[i];


           if (typeof point !== 'object' || point === null || !('x' in point) || !('y' in point) ) {
                console.error("CanvasLayer: Invalid data point format detected", point, id);
                continue; // Skip if not valid point.
            }

          if(point.gap === true){  // Gap detected.
              ctx.stroke(); // Stroke and end the path.
           ctx.beginPath(); // Start a new path from new point.
           ctx.strokeStyle = 'red'; // Draw the current line as red, for test, you can set the color as your requirement.
            if(prevX !== null && prevY != null)  ctx.moveTo(prevX, prevY);
          } else {
             ctx.strokeStyle = color; // draw a normal line.
            }

            ctx.lineTo(point.x, point.y); // Draw segment.
           prevX = point.x;  // store current x and y values.
           prevY = point.y;

         }

          ctx.stroke();  // Draw last segment

     };


</script>

<canvas style="background-color:transparent" bind:this={canvas} {width} {height}></canvas>