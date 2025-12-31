<script lang="ts">
  import { onMount, onDestroy } from "svelte";

  let { src, alt = "Logo", class: className = "" }: {
    src: string;
    alt?: string;
    class?: string;
  } = $props();

  let logoElement: HTMLImageElement;
  let beatInterval: ReturnType<typeof setInterval> | null = null;
  let currentMultiplier = 1.0;

  function startPulsating(multiplier: number) {
    if (beatInterval) {
      clearInterval(beatInterval);
    }

    if (multiplier <= 1.0) {
      return;
    }

    const baseInterval = 2000;
    const msPerBeat = baseInterval / multiplier;

    triggerPulse();

    beatInterval = setInterval(() => {
      triggerPulse();
    }, msPerBeat);
  }

  function triggerPulse() {
    if (!logoElement) return;
    logoElement.classList.add('pulsing');
    setTimeout(() => {
      if (logoElement) {
        logoElement.classList.remove('pulsing');
      }
    }, 200);
  }

  function updateFromMetrics() {
    const metricsEl = document.querySelector('[id="system-metrics"]');
    if (!metricsEl) return;

    const multiplierText = metricsEl.textContent || '';
    const match = multiplierText.match(/x\s*([\d.]+)/);
    if (match) {
      const newMultiplier = parseFloat(match[1]);
      if (!isNaN(newMultiplier) && newMultiplier !== currentMultiplier) {
        currentMultiplier = newMultiplier;
        startPulsating(newMultiplier);
      }
    }
  }

  onMount(() => {
    updateFromMetrics();

    const observer = new MutationObserver(() => {
      updateFromMetrics();
    });

    const metricsEl = document.querySelector('[id="system-metrics"]');
    if (metricsEl) {
      observer.observe(metricsEl, { childList: true, subtree: true, characterData: true });
    }

    const refreshInterval = setInterval(updateFromMetrics, 2000);

    return () => {
      observer.disconnect();
      clearInterval(refreshInterval);
    };
  });

  onDestroy(() => {
    if (beatInterval) {
      clearInterval(beatInterval);
    }
  });
</script>

<img
  bind:this={logoElement}
  {src}
  {alt}
  class="pulsating-logo {className}"
/>

<style>
  .pulsating-logo {
    transition: transform 0.15s ease-out, filter 0.15s ease-out;
  }

  :global(.pulsating-logo.pulsing) {
    transform: scale(1.08);
    filter: brightness(1.2) drop-shadow(0 0 8px rgba(239, 68, 68, 0.6));
  }
</style>
