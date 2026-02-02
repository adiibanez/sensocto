function getCookie(name) {
    const cookies = document.cookie.split(';');
    for (let i = 0; i < cookies.length; i++) {
        const cookie = cookies[i].trim();
        if (cookie.startsWith(name + '=')) {
            return decodeURIComponent(cookie.substring(name.length + 1));
        }
    }
    return null; // Cookie not found
}

function setCookie(name, value, days = 365) {
    let expires = "";
    if (days) {
        const date = new Date();
        date.setTime(date.getTime() + (days * 24 * 60 * 60 * 1000));
        expires = "; expires=" + date.toUTCString();
    }
    document.cookie = name + "=" + encodeURIComponent(value) + expires + "; path=/"; // Important: Set path=/ for site-wide access
}

/**
 * Get a session-scoped value (unique per browser tab).
 * Uses sessionStorage which is not shared between tabs.
 */
function getSessionValue(name) {
    return sessionStorage.getItem(name);
}

/**
 * Set a session-scoped value (unique per browser tab).
 * Uses sessionStorage which is not shared between tabs.
 */
function setSessionValue(name, value) {
    sessionStorage.setItem(name, value);
}

function isMobile() {
    const ua = navigator.userAgent;

    // Classic mobile detection (phones and older tablets)
    const isMobileUA = /iPhone|iPad|iPod|Android/i.test(ua);

    // iPadOS 13+ reports as Mac, but has touch support
    // Detect by checking for touch capability on Mac platform
    const isIPadOS = (
        navigator.platform === 'MacIntel' &&
        navigator.maxTouchPoints > 0
    ) || (
        // Alternative: Mac with touch in user agent platform
        /Mac/.test(navigator.platform) &&
        'ontouchend' in document
    );

    // Android tablets: Check for Android + touch but no "Mobile" in UA
    // (Android phones have "Mobile" in UA, tablets don't)
    const isAndroidTablet = /Android/i.test(ua) && !/Mobile/i.test(ua);

    return isMobileUA || isIPadOS || isAndroidTablet;
}


export { getCookie, setCookie, getSessionValue, setSessionValue, isMobile };