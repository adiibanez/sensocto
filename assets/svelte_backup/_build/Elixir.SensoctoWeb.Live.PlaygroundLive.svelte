<script>
  export let number = 5
  let other = 1

  $: combined = other + number
</script>

<p>This is number: {number}</p>
<p>This is other: {other}</p>
<p>This is other + number: {combined}</p>

<button phx-click="increment">Increment</button>
<button on:click={() => other += 1}>Increment</button>
