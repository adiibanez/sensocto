import init, { draw_sparkline } from './pkg/your_project_name.js'; // Adjust path

async function run() {
  await init();

  const canvas = document.getElementById('sparkline-canvas');
  const ctx = canvas.getContext('2d');

  const width = canvas.width;
  const height = canvas.height;
   // Data array (example)
   let data = [10, 20, 15, 25, 18, 30, 20, 28];

   function render() {
      draw_sparkline(data, width, height, ctx);
   }
   
   render();
  // An example of data update
  let counter = 0;
  setInterval(()=>{
    data = data.map(x => x +  (Math.random() - 0.5) * 10);
    counter ++;
    render();

  }, 50);
}
run();