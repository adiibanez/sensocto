use wasm_bindgen::prelude::*;
use std::f64;
use std::cmp::Ordering;

#[wasm_bindgen]
extern "C" {
    #[wasm_bindgen(js_namespace = console)]
    fn log(s: &str);
    #[wasm_bindgen(js_namespace = console, js_name = log)]
      fn log_object(x: &JsValue);

    #[wasm_bindgen(extends = js_sys::Object, js_name = CanvasRenderingContext2D)]
    #[derive(Debug, Clone, PartialEq, Eq)]
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

    //#[wasm_bindgen(method, js_name = setStrokeStyle)]
    //fn set_stroke_style(this: &CanvasRenderingContext2d, color: &str);

    //#[wasm_bindgen(method, js_name = setLineWidth)]
    //fn set_line_width(this: &CanvasRenderingContext2d, width: f64);
    
    #[wasm_bindgen(method, js_name = setLineDash)]
    fn set_line_dash(this: &CanvasRenderingContext2d, segments: &[f64]);

     #[wasm_bindgen(method, js_name = fillText)]
    fn fill_text(this: &CanvasRenderingContext2d, text: &str, x: f64, y: f64);
    #[wasm_bindgen(method, js_name = rect)]
    fn rect(this: &CanvasRenderingContext2d, x: f64, y: f64, width: f64, height: f64);
}
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
struct DataPoint {
    timestamp: f64,
    payload: f64,
}

fn smooth(data: &[DataPoint], factor: usize) -> Vec<DataPoint> {
    if data.len() < factor {
       return data.to_vec();
    }
     let mut smoothed = Vec::with_capacity(data.len());

     for i in 0..data.len(){
        let start = if i < factor {0} else {i - factor};
        let end = (i + factor + 1).min(data.len());
       let sum = data[start..end].iter().map(|x| x.payload).sum::<f64>();
       let avg = sum / (end - start) as f64;
       let avg_timestamp = data[start..end].iter().map(|x| x.timestamp).sum::<f64>() / (end - start) as f64;

        smoothed.push(DataPoint {
            timestamp: avg_timestamp,
            payload: avg,
        });
    }
    smoothed
}

#[wasm_bindgen]
pub fn draw_sparkline(
    data: &JsValue,
    width: u32,
    height: u32,
    ctx: &JsValue,
    line_color: &str,
    line_width: f64,
    smoothing: usize,
    time_window: f64,
    burst_threshold: f64,
    operation_mode: &str,
      draw_scales: bool,
    min_value: Option<f64>,
    max_value: Option<f64>,
) {
    log("Calling draw_sparkline from Wasm");
     log("Logging Context Object");
     log_object(&ctx);
   //convert the JsValue to canvas object
     let ctx: CanvasRenderingContext2d = ctx.clone().into();

    // Clear canvas
    ctx.clear_rect(0.0, 0.0, width as f64, height as f64);
    //ctx.set_stroke_style(line_color);
    //ctx.set_line_width(line_width);
   
    let mut data_points: Vec<DataPoint> = Vec::new();

     if let Ok(vec) = serde_wasm_bindgen::from_value::<Vec<serde_json::Value>>(data.clone()){
          for item in vec {
                if let serde_json::Value::Object(obj) = item {
                  if let (Some(serde_json::Value::Number(ts)), Some(serde_json::Value::Number(payload))) = (obj.get("timestamp"), obj.get("payload")) {
                    if let (Some(ts), Some(payload)) = (ts.as_f64(), payload.as_f64()){
                        data_points.push(DataPoint{timestamp: ts, payload: payload});
                     }
                   }
                 }
            }
      }else{
        return;
    }

    if data_points.is_empty() {
        return;
    }
   data_points.sort_by(|a,b| a.timestamp.partial_cmp(&b.timestamp).unwrap_or(Ordering::Equal));

    let now = if let Some(last) = data_points.last() {last.timestamp} else {0f64};
  

  let filtered_data: Vec<DataPoint> = if operation_mode == "absolute" {
      data_points.into_iter().filter(|x| now - x.timestamp <= time_window * 1000f64 ).collect()
    } else {
      data_points
    };


  let smoothed_data = smooth(&filtered_data, smoothing);
   
    if smoothed_data.is_empty() {
        return;
    }
  
     let min = match min_value {
      Some(v) => v,
      None => smoothed_data.iter().fold(f64::INFINITY, |a, b| f64::min(a, b.payload)),
       };
  
    let max = match max_value {
       Some(v) => v,
        None => smoothed_data.iter().fold(f64::NEG_INFINITY, |a, b| f64::max(a, b.payload)),
    };
    let data_len = smoothed_data.len() as f64;
    let width_f64 = width as f64;
    let height_f64 = height as f64;

    ctx.begin_path();
    
     let mut last_timestamp = 0f64;
    for (i, point) in smoothed_data.iter().enumerate(){
        let x = (i as f64) / data_len * width_f64;
        let y = if max == min {
            height_f64 / 2.0
        } else {
             height_f64 - (point.payload - min) / (max - min) * height_f64
       };
       
     if operation_mode == "relative" && last_timestamp != 0f64{
           if  point.timestamp - last_timestamp > burst_threshold * 1000f64 {
           log("Gap detected");
                ctx.set_line_dash(&[10.0, 5.0]);
                 if i > 0 {
                       let last_point = &smoothed_data[i - 1];
                     let last_x = ((i - 1) as f64) / data_len * width_f64;
                       let last_y = if max == min {
                         height_f64 / 2.0
                        } else {
                        height_f64 - (last_point.payload - min) / (max - min) * height_f64
                    };
                        ctx.move_to(last_x, last_y);
                        ctx.line_to(x, y);
                       ctx.stroke();
                      ctx.set_line_dash(&[]);

                       ctx.rect(x - 5f64, 0f64, 5f64, height_f64);
                       ctx.stroke();
                }
            
           }
     }
    
      last_timestamp = point.timestamp;

    if i == 0 {
       ctx.move_to(x, y);
    } else {
       ctx.line_to(x, y);
    }
    }
      ctx.stroke();
      if draw_scales {
           let min_str = format!("{:.2}", min);
            ctx.fill_text(&min_str, 5f64, height_f64 - 5f64);
            let max_str = format!("{:.2}", max);
            ctx.fill_text(&max_str, 5f64, 10f64);
        }
}