<svelte:options customElement="sparkline-test" />
<svelte:window on:dataupdate={handleTestEvent} />

<script>
    import {
        getContext,
        createEventDispatcher,
        onDestroy,
        onMount
    } from "svelte";
    import Canvas from "./Canvas.svelte";
    import ScaledPoints from "./ScaledPoints.svelte";
    import Point from "./Point.svelte";

    export let debugFlag = false;
    export let canvas;
    export let scaledPoints;

    export let test = [];

    export let width = 100;
    export let height = 50;
    export let data = [];
    export let appenddata;
    export let timeMode = "relative";
    export let timeWindow = 0.5 * 60 * 1000;
    export let yPadding = 0.2;
    export let maxlength;
    export let points = [];

    $: width = Math.floor(parseFloat(width));
    $: height = Math.floor(parseFloat(height));

    $: if (appenddata?.length) {
        console.log("Sparkline: appenddata ", appenddata, typeof appenddata);
        appenddata = JSON.parse(appenddata);
    }

    $: if (points?.length) {
        //canvas.$set({ points: points });
        console.log("Sparkline scaledPoints changed");
    }

    $: if (data?.length) {
        if (debugFlag)
            console.log(
                "Sparkline: data changed, redrawing sparkline...",
                data,
            );
    }

    $: if(scaledPoints?.points) {
        console.log("Sparkline scaledPoints changed");
    }

    onMount(() => {
        console.log("Sparkline: onMount", canvas);
    });

    const handleTestEvent = (e) => {
        console.log("Sparkline: test event received", e);
    };
</script>

<div on:dataupdate={handleTestEvent} {width} {height}>
    <ScaledPoints
        bind:this={scaledPoints}
        bind:data
        bind:scaledPoints={test}
        {width}
        {height}
        {timeMode}
        {timeWindow}
        {yPadding}
        {debugFlag}
    ></ScaledPoints>

    <Canvas bind:this={canvas} bind:points={test} {width} {height} {debugFlag}></Canvas>

    <ul>
        {#each points as { x, y } (id)}
            <li><Point {x} {y} /></li>
        {/each}
    </ul>

    {#if true  }<p>Sparkline DATA: maxLength: {maxlength} {data.length} Points: {test.length}</p>{/if}
</div>
