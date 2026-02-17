// connection-monitor.js
// Unified connection state monitor for LiveSocket + SensorService socket.
// Exposes state on window.__sensocto_connection and dispatches events.

const STATES = { ONLINE: 'online', DEGRADED: 'degraded', OFFLINE: 'offline', SYNCING: 'syncing' };

function createConnectionMonitor() {
  const state = {
    status: STATES.ONLINE,
    liveSocket: true,
    sensorSocket: true,
    bufferedCount: 0,
    since: null,
  };

  const listeners = new Set();

  function computeStatus() {
    if (state.bufferedCount > 0 && state.liveSocket && state.sensorSocket) return STATES.SYNCING;
    if (!state.liveSocket && !state.sensorSocket) return STATES.OFFLINE;
    if (!state.liveSocket || !state.sensorSocket) return STATES.DEGRADED;
    return STATES.ONLINE;
  }

  function update(partial) {
    Object.assign(state, partial);
    const newStatus = computeStatus();
    const changed = newStatus !== state.status;
    state.status = newStatus;
    if (newStatus === STATES.OFFLINE && !state.since) {
      state.since = Date.now();
    } else if (newStatus === STATES.ONLINE) {
      state.since = null;
    }
    if (changed || partial.bufferedCount !== undefined) {
      notify();
    }
  }

  function notify() {
    const detail = { ...state };
    listeners.forEach(fn => fn(detail));
    window.dispatchEvent(new CustomEvent('sensocto:connection-change', { detail }));
  }

  function subscribe(fn) {
    listeners.add(fn);
    fn({ ...state });
    return () => listeners.delete(fn);
  }

  // Monitor the LiveSocket (set up after liveSocket is available)
  function watchLiveSocket(liveSocket) {
    if (!liveSocket?.socket) return;
    const sock = liveSocket.socket;

    sock.onOpen(() => update({ liveSocket: true }));
    sock.onClose(() => update({ liveSocket: false }));
    sock.onError(() => update({ liveSocket: false }));
  }

  return {
    STATES,
    get state() { return { ...state }; },
    update,
    subscribe,
    notify,
    watchLiveSocket,
    setBufferedCount(count) { update({ bufferedCount: count }); },
    setSensorSocket(connected) { update({ sensorSocket: connected }); },
  };
}

const monitor = createConnectionMonitor();
window.__sensocto_connection = monitor;

export default monitor;
