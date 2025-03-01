import { writable } from 'svelte/store';

export const autostart = writable(false);

export const usersettings = writable({
    autostart: false,
    deviceName: ''
});