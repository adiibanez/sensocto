use wasm_bindgen::prelude::*;
use std::f64;

#[wasm_bindgen]
extern "C" {
    #[wasm_bindgen(js_namespace = console)]
    fn log(s: &str);

    type CanvasRenderingContext2d;
    #[wasm_bindgen(method, js_name = beginPath)]
    fn begin_path(this: &CanvasRenderingContext2d);

     #[wasm_bindgen(method, js_name = moveTo)]
    fn move_to(this: &CanvasRenderingContext2d, x: f64, y: f64);

    #[wasm_bindgen(method, js_name = lineTo)]
    fn line_to(this: &CanvasRenderingContext2d, x: f64, y: f64);

    #[wasm_bindgen(method, js_name = stroke)]
    fn stroke(this: &CanvasRenderingContext2d);

     #[wasm_bindgen(method, js_name = clearRect)]
     fn clear_rect(this: &CanvasRenderingContext2d, x: f64, y: f64, width: f64, height: f64);
}

#[wasm_bindgen]
pub fn draw_sparkline(data: &[f64], width: u32, height: u32, ctx: &CanvasRenderingContext2d) {
    log("Calling draw_sparkline from Wasm");

    // Clear canvas
    ctx.clear_rect(0.0, 0.0, width as f64, height as f64);


    if data.is_empty() {
        return;
    }
    // Find min and max value for scaling
    let min = data.iter().fold(f64::INFINITY, |a, &b| a.min(b));
    let max = data.iter().fold(f64::NEG_INFINITY, |a, &b| a.max(b));

     let data_len = data.len() as f64;
     let width_f64 = width as f64;
    let height_f64 = height as f64;


    ctx.begin_path();
    for (i, &value) in data.iter().enumerate() {
        let x = (i as f64) / data_len * width_f64;
        let y = if max == min {
            height_f64 / 2.0
        }else {
           height_f64 - (value - min) / (max - min) * height_f64
       };


        if i == 0 {
            ctx.move_to(x, y);
        } else {
            ctx.line_to(x, y);
        }


    }
    ctx.stroke();
}