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
    const isMobile = /iPhone|iPad|iPod|Android/i.test(navigator.userAgent);
    return isMobile;
}


export { getCookie, setCookie, getSessionValue, setSessionValue, isMobile };