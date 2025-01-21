<script>
    let db = 0;
    let error = null;
    let isAnalyzing = false;
    let stream = null; // Store the stream to stop it later
  
    const toggleAnalyzer = () => {
      isAnalyzing = !isAnalyzing;
  
      if (isAnalyzing) {
        startAnalyzing();
      } else {
        stopAnalyzing();
      }
    };
  
    const startAnalyzing = () => {
      const audioContext = new AudioContext();
      const analyser = audioContext.createAnalyser();
      const scriptProcessor = audioContext.createScriptProcessor(2048, 1, 1);
  
      analyser.smoothingTimeConstant = 0.8;
      analyser.fftSize = 1024;
  
      navigator.mediaDevices.getUserMedia({ audio: true })
        .then(str => {
          stream = str; // Store the stream
          const microphone = audioContext.createMediaStreamSource(stream);
  
          microphone.connect(analyser);
          analyser.connect(scriptProcessor);
          scriptProcessor.connect(audioContext.destination);
  
          scriptProcessor.onaudioprocess = () => {
            const array = new Uint8Array(analyser.frequencyBinCount);
            analyser.getByteFrequencyData(array);
  
            let sumSquares = 0;
            for (let i = 0; i < array.length; i++) {
              sumSquares += array[i] * array[i];
            }
  
            const rms = Math.sqrt(sumSquares / array.length);
            db = 20 * Math.log10(rms);
  
            // Important: Check for NaN/Infinity even in active mode
            if (isNaN(db) || !isFinite(db)) db = -Infinity; 
          };
        })
        .catch(err => {
          error = "Error accessing microphone: " + err.message;
          console.error(error);
          isAnalyzing = false; // Reset if there's an error
        });
    };
  
  
    const stopAnalyzing = () => {
      if (stream) {  // Stop only if stream exists
        stream.getTracks().forEach(track => track.stop());
        stream = null;  // Clear the stream reference
        db = 0;        // Reset the db value
      }
    };
  
  </script>
  
  
  <button on:click={toggleAnalyzer}>
    {isAnalyzing ? "Stop Analyzing" : "Start Analyzing"}
  </button>
  
  {#if error}
    <p style="color: red">{error}</p>
  {:else if isAnalyzing}  <!-- Only show dB when analyzing -->
    <p>DB: {db.toFixed(1)} dB</p>
  {/if}