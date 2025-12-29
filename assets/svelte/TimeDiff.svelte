<script>
    import { onMount } from "svelte";

    export let startTime; // Expects a Date object or a timestamp (number)

    let timerInterval;
    let formattedTime;
    let currentStartTime; // Track the current startTime to detect changes

    $: if (startTime) {
        // Clear existing interval when startTime changes to reset the timer
        if (currentStartTime !== startTime) {
            clearInterval(timerInterval);
            timerInterval = undefined;
            currentStartTime = startTime;
        }

        // Calculate the initial time difference
        formatTimeDifference(getTimeDifference());
    }

    function getTimeDifference() {
        return Date.now() - currentStartTime;
    }

    function formatTimeDifference(difference) {
        if (difference < 1000) {
            if (timerInterval == undefined) {
                timerInterval = setInterval(() => {
                    formatTimeDifference(getTimeDifference());
                }, 100);
            }
            formattedTime = `${getTimeDifference().toFixed(0)} ms ago`;
        } else if (difference < 60 * 1000) {
            // Less than a minute has passed:
            let diffSec = (difference / 1000).toFixed(1);
            formattedTime = `${diffSec} sec${diffSec > 1 ? "s" : ""} ago`;

            if (timerInterval == undefined) {
                timerInterval = setInterval(() => {
                    formatTimeDifference(getTimeDifference());
                }, 1000);
            }
        } else if (difference < 3600 * 1000) {
            // Less than an hour has passed:
            let diffMin = Math.floor(difference / 60 / 1000);
            formattedTime = `${diffMin} min${diffMin > 1 ? "s" : ""} ago`;
            if (timerInterval == undefined) {
                timerInterval = setInterval(() => {
                    formatTimeDifference(getTimeDifference());
                }, 1000 * 60);
            }
        } else if (difference < 86400 * 1000) {
            // Less than a day has passed:
            formattedTime = `${Math.floor(difference / 3600 / 1000)} hours ago`;
            clearInterval(timerInterval);
            timerInterval = undefined;
        } else if (difference < 2620800 * 1000) {
            // Less than a month has passed:
            formattedTime = `${Math.floor(difference / 86400 / 1000)} days ago`;
            clearInterval(timerInterval);
            timerInterval = undefined;
        } else if (difference < 31449600 * 1000) {
            // Less than a year has passed:
            formattedTime = `${Math.floor(difference / 2620800 / 1000)} months ago`;
            clearInterval(timerInterval);
            timerInterval = undefined;
        } else {
            // More than a year has passed:
            formattedTime = `${Math.floor(difference / 31449600 / 1000)} years ago`;
            clearInterval(timerInterval);
            timerInterval = undefined;
        }
    }

    onMount(() => {
        return () => {
            clearInterval(timerInterval);
        };
    });
</script>

<span>{formattedTime}</span>
