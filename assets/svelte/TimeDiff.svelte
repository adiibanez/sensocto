<script>
    import { onMount } from "svelte";

    export let startTime; // Expects a Date object or a timestamp (number)

    let timerInterval;
    let formattedTime;

    $: if (startTime) {
        const startTimestamp =
            startTime instanceof Date ? startTime.getTime() : startTime;

        // Calculate the initial time difference.  Important if component is mounted later.
        formatTimeDifference(getTimeDifference());
    }

    function getTimeDifference() {
        return Date.now() - startTime;
    }

    function formatTimeDifference(difference) {
        if (difference < 1000) {
            if (timerInterval == undefined) {
                timerInterval = setInterval(() => {
                    formatTimeDifference(getTimeDifference());
                }, 100); // Update every millisecond
            }
            formattedTime = `${getTimeDifference().toFixed(0)} ms ago`;
        } else if (difference < 60 * 1000) {
            // Less than a minute has passed:
            diffSec = (difference / 1000).toFixed(1);
            formattedTime = `${diffSec} sec${diffSec > 1 ? "s" : ""} ago`;

            if (timerInterval == undefined) {
                timerInterval = setInterval(() => {
                    formatTimeDifference(getTimeDifference());
                }, 1000); // Update every second
            }
        } else if (difference < 3600 * 1000) {
            // Less than an hour has passed:
            diffMin = Math.floor(difference / 60 / 1000);
            formattedTime = `${diffMin} min${diffMin > 1 ? "s" : ""} ago`;
            if (timerInterval == undefined) {
                timerInterval = setInterval(() => {
                    formatTimeDifference(getTimeDifference());
                }, 1000 * 60); // Update every minute
            }
        } else if (difference < 86400 * 1000) {
            // Less than a day has passed:
            formattedTime = `${Math.floor(difference / 3600 / 1000)} hours ago`;
            clearInterval(timerInterval);
        } else if (difference < 2620800 * 1000) {
            // Less than a month has passed:
            formattedTime = `${Math.floor(difference / 86400 / 1000)} days ago`;
            clearInterval(timerInterval);
        } else if (difference < 31449600 * 1000) {
            // Less than a year has passed:
            formattedTime = `${Math.floor(difference / 2620800 / 1000)} months ago`;
            clearInterval(timerInterval);
        } else {
            // More than a year has passed:
            formattedTime = `${Math.floor(difference / 31449600 / 1000)} years ago`;
            clearInterval(timerInterval);
        }
    }

    onMount(() => {
        return () => {
            clearInterval(timerInterval);
        };
    });
</script>

<span>{formattedTime}</span>
