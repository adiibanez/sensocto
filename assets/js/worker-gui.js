// worker.js

function processAccumulation({ accumulatedSelector, sparkLineSelector, accumulatedString, appendString, maxLength }) {
    const startTime = performance.now();

    console.log('before processAccumulation', accumulatedString);

     try {
         let accumulatedData = JSON.parse(accumulatedString)
         const appendData = JSON.parse(appendString);
          accumulatedData.push(appendData)
  
        if (accumulatedData.length > maxLength) {
            accumulatedData = accumulatedData.slice(-maxLength);
        }
  
         const endTime = performance.now();
          const elapsedTime = endTime - startTime;
  
      return {
          accumulatedSelector: accumulatedSelector,
          sparkLineSelector: sparkLineSelector,
          accumulatedString: JSON.stringify(accumulatedData),
          maxLength: maxLength,
          elapsedTime: elapsedTime
      };
  
      } catch (error){
          const endTime = performance.now();
          const elapsedTime = endTime - startTime;

          console.log('processAccumulation', error);
  
       /*return {
            accumulatedSelector: accumulatedSelector,
            sparkLineSelector: sparkLineSelector,
            accumulatedString: "Error parsing data",
            maxLength: maxLength,
             elapsedTime: elapsedTime
          };*/
      }
  }
  
  self.addEventListener('message', function(event) {
    const { type, data } = event.data;
  
    if (type === 'process-accumulation') {
      const result = processAccumulation(data);
      self.postMessage({ type: 'accumulation-result', data: result });
    }
  });