import QRCodeLib from 'qrcode';

/**
 * RoomStorage Hook
 *
 * Manages room configurations in localStorage for bootstrapping temporary rooms.
 * Allows users to save room configurations locally and restore them across sessions.
 */

const STORAGE_KEY = 'sensocto_rooms';

export const RoomStorage = {
  mounted() {
    // Load saved room configurations from localStorage on mount
    this.loadFromStorage();

    // Handle save events from LiveView
    this.handleEvent('save_room_to_storage', ({ room }) => {
      this.saveRoom(room);
    });

    // Handle remove events from LiveView
    this.handleEvent('clear_room_from_storage', ({ room_id }) => {
      this.removeRoom(room_id);
    });

    // Handle clear all events
    this.handleEvent('clear_all_rooms_from_storage', () => {
      this.clearAll();
    });
  },

  /**
   * Load all saved rooms from localStorage and push to LiveView
   */
  loadFromStorage() {
    try {
      const savedRooms = JSON.parse(localStorage.getItem(STORAGE_KEY) || '[]');

      if (savedRooms.length > 0) {
        console.log('[RoomStorage] Loaded rooms from storage:', savedRooms.length);
        this.pushEvent('rooms_loaded_from_storage', { rooms: savedRooms });
      }
    } catch (error) {
      console.error('[RoomStorage] Failed to load from storage:', error);
    }
  },

  /**
   * Save a room configuration to localStorage
   */
  saveRoom(room) {
    try {
      const rooms = JSON.parse(localStorage.getItem(STORAGE_KEY) || '[]');

      // Remove existing room with same ID if present
      const filteredRooms = rooms.filter(r => r.id !== room.id);

      // Add the new/updated room
      filteredRooms.push({
        id: room.id,
        name: room.name,
        description: room.description,
        join_code: room.join_code,
        is_public: room.is_public,
        configuration: room.configuration,
        saved_at: new Date().toISOString()
      });

      localStorage.setItem(STORAGE_KEY, JSON.stringify(filteredRooms));
      console.log('[RoomStorage] Saved room:', room.id);
    } catch (error) {
      console.error('[RoomStorage] Failed to save room:', error);
    }
  },

  /**
   * Remove a room from localStorage
   */
  removeRoom(roomId) {
    try {
      const rooms = JSON.parse(localStorage.getItem(STORAGE_KEY) || '[]');
      const filteredRooms = rooms.filter(r => r.id !== roomId);
      localStorage.setItem(STORAGE_KEY, JSON.stringify(filteredRooms));
      console.log('[RoomStorage] Removed room:', roomId);
    } catch (error) {
      console.error('[RoomStorage] Failed to remove room:', error);
    }
  },

  /**
   * Clear all saved rooms from localStorage
   */
  clearAll() {
    try {
      localStorage.removeItem(STORAGE_KEY);
      console.log('[RoomStorage] Cleared all saved rooms');
    } catch (error) {
      console.error('[RoomStorage] Failed to clear storage:', error);
    }
  }
};

/**
 * CopyToClipboard Hook
 *
 * Copies text to clipboard when element is clicked.
 * Expects data-copy-text attribute with the text to copy.
 */
export const CopyToClipboard = {
  mounted() {
    this.el.addEventListener('click', async (e) => {
      const text = this.el.dataset.copyText;

      if (!text) {
        console.warn('[CopyToClipboard] No text to copy');
        return;
      }

      try {
        await navigator.clipboard.writeText(text);
        console.log('[CopyToClipboard] Copied:', text);

        // Visual feedback
        const originalText = this.el.textContent;
        this.el.textContent = 'Copied!';
        setTimeout(() => {
          this.el.textContent = originalText;
        }, 2000);
      } catch (error) {
        console.error('[CopyToClipboard] Failed to copy:', error);

        // Fallback for older browsers
        const textarea = document.createElement('textarea');
        textarea.value = text;
        textarea.style.position = 'fixed';
        textarea.style.opacity = '0';
        document.body.appendChild(textarea);
        textarea.select();
        document.execCommand('copy');
        document.body.removeChild(textarea);
      }
    });
  }
};

/**
 * QRCode Hook
 *
 * Generates a QR code for the given value using the qrcode library.
 */
export const QRCode = {
  mounted() {
    this.generateQRCode();
  },

  updated() {
    this.generateQRCode();
  },

  async generateQRCode() {
    const value = this.el.dataset.value;

    if (!value) {
      console.warn('[QRCode] No value provided');
      return;
    }

    try {
      const canvas = document.createElement('canvas');
      await QRCodeLib.toCanvas(canvas, value, {
        width: 192,
        margin: 2,
        color: {
          dark: '#000000',
          light: '#ffffff'
        }
      });
      this.el.innerHTML = '';
      this.el.appendChild(canvas);
    } catch (error) {
      console.error('[QRCode] Failed to generate QR code:', error);
      this.el.innerHTML = '<p style="color: red;">Failed to generate QR code</p>';
    }
  }
};
