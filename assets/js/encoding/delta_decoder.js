/**
 * Delta decoder for high-frequency ECG data.
 * Mirrors Elixir Sensocto.Encoding.DeltaEncoder.
 *
 * Binary format:
 *   [Header: 1 byte] [Base Timestamp: 8 bytes] [First Value: 4 bytes] [Deltas...]
 *
 *   Delta entry:
 *     Normal: [int8 value_delta] [uint16 timestamp_delta_ms]
 *     Reset:  [-128 (0x80)] [float32 new_value] [uint16 timestamp_delta_ms]
 */

const QUANTIZATION_STEP = 0.01;
const RESET_MARKER = -128; // int8 representation of 0x80
const VERSION = 0x01;

/**
 * Decode delta-encoded ECG data from base64.
 * @param {string} base64Data - Base64 encoded binary
 * @returns {Array<{timestamp: number, payload: number}>|null}
 */
export function decodeECG(base64Data) {
  try {
    const binary = atob(base64Data);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) {
      bytes[i] = binary.charCodeAt(i);
    }

    const view = new DataView(bytes.buffer);
    let offset = 0;

    // Header
    const header = bytes[offset++];
    const version = header & 0x0f;
    if (version !== VERSION) return null;

    // Base timestamp (int64 little-endian)
    const baseTimestampLow = view.getUint32(offset, true);
    const baseTimestampHigh = view.getInt32(offset + 4, true);
    let currentTimestamp = baseTimestampHigh * 0x100000000 + baseTimestampLow;
    offset += 8;

    // First value (float32 little-endian)
    let currentValue = view.getFloat32(offset, true);
    offset += 4;

    const measurements = [{ timestamp: currentTimestamp, payload: currentValue }];

    // Decode deltas
    while (offset < bytes.length) {
      const valueDelta = view.getInt8(offset++);

      if (valueDelta === RESET_MARKER) {
        // Reset: read new full float32
        currentValue = view.getFloat32(offset, true);
        offset += 4;
      } else {
        currentValue += valueDelta * QUANTIZATION_STEP;
      }

      // Timestamp delta (uint16 little-endian)
      const timestampDelta = view.getUint16(offset, true);
      offset += 2;
      currentTimestamp += timestampDelta;

      measurements.push({ timestamp: currentTimestamp, payload: currentValue });
    }

    return measurements;
  } catch (e) {
    console.error("[DeltaDecoder] decode failed:", e);
    return null;
  }
}

/**
 * Check if data is delta-encoded.
 * @param {*} data
 * @returns {boolean}
 */
export function isDeltaEncoded(data) {
  return data != null && data.__delta_encoded__ === true;
}
