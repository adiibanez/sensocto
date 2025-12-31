<script lang="ts">
  import { onMount, onDestroy } from "svelte";

  let { sensor_id, attribute_id, bpm = 60, size = "large" }: {
    sensor_id: string;
    attribute_id: string;
    bpm?: number;
    size?: "small" | "large";
  } = $props();

  let heartElement: SVGElement;
  let beatInterval: ReturnType<typeof setInterval> | null = null;
  let currentBpm = bpm;

  function startHeartbeatFromBpm(targetBpm: number) {
    if (beatInterval) {
      clearInterval(beatInterval);
    }

    if (targetBpm <= 0 || targetBpm > 300) return;

    const msPerBeat = 60000 / targetBpm;

    triggerPulse();

    beatInterval = setInterval(() => {
      triggerPulse();
    }, msPerBeat);
  }

  function triggerPulse() {
    if (!heartElement) return;
    heartElement.classList.add('pulsing');
    setTimeout(() => {
      if (heartElement) {
        heartElement.classList.remove('pulsing');
      }
    }, 200);
  }

  onMount(() => {
    const handleAccumulatorEvent = (e: CustomEvent) => {
      if (
        sensor_id === e?.detail?.sensor_id &&
        attribute_id === e?.detail?.attribute_id
      ) {
        const newBpm = e?.detail?.payload;
        if (typeof newBpm === "number" && newBpm > 0 && newBpm !== currentBpm) {
          currentBpm = newBpm;
          startHeartbeatFromBpm(newBpm);
        }
      }
    };

    window.addEventListener(
      "accumulator-data-event",
      handleAccumulatorEvent as EventListener
    );

    if (bpm > 0) {
      startHeartbeatFromBpm(bpm);
    }

    return () => {
      window.removeEventListener(
        "accumulator-data-event",
        handleAccumulatorEvent as EventListener
      );
    };
  });

  onDestroy(() => {
    if (beatInterval) {
      clearInterval(beatInterval);
    }
  });
</script>

<div class="heartbeat-container {size}">
  <svg
    bind:this={heartElement}
    class="heart-icon"
    viewBox="0 0 24 24"
    fill="currentColor"
  >
    <path d="M11.645 20.91l-.007-.003-.022-.012a15.247 15.247 0 01-.383-.218 25.18 25.18 0 01-4.244-3.17C4.688 15.36 2.25 12.174 2.25 8.25 2.25 5.322 4.714 3 7.688 3A5.5 5.5 0 0112 5.052 5.5 5.5 0 0116.313 3c2.973 0 5.437 2.322 5.437 5.25 0 3.925-2.438 7.111-4.739 9.256a25.175 25.175 0 01-4.244 3.17 15.247 15.247 0 01-.383.219l-.022.012-.007.004-.003.001a.752.752 0 01-.704 0l-.003-.001z" />
  </svg>
</div>

<style>
  .heartbeat-container {
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .heartbeat-container.small .heart-icon {
    width: 1rem;
    height: 1rem;
  }

  .heartbeat-container.large .heart-icon {
    width: 4rem;
    height: 4rem;
  }

  .heart-icon {
    color: #ef4444;
    transition: transform 0.1s ease-out;
  }

  :global(.heart-icon.pulsing) {
    transform: scale(1.25);
  }
</style>
