<script lang="ts">
  // We added export to make it reactive with the server
  
  interface Props {
    // Number is set to 10
    number?: number;
  }

  let { number = 1 }: Props = $props();

  // Let's combine local state with server state
  let number2 = $state(5)

  let combined = $derived(number + number2)
</script>

{number} + {number2} = {combined}

<button class="rounded" phx-click="increment">increment</button>
<button class="rounded" onclick={() => number2 += 1}>increment</button>

<style lang="stylus">
  button
    background-color black
    color white
    padding 0.5rem 1rem
</style>
