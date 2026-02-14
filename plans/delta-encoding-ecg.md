# Delta Encoding for High-Frequency ECG Data

**Status**: Planned
**Created**: 2026-01-30
**Expected Bandwidth Reduction**: ~84%

## Overview

Implement delta encoding for ECG waveform data to reduce WebSocket bandwidth while preserving existing functionality through a feature flag.

**Before**: 50 samples = ~1000 bytes (JSON)
**After**: 50 samples = ~162 bytes (binary)

---

## Phase 1: Elixir Encoder Module

**Create** `lib/sensocto/encoding/delta_encoder.ex`

```elixir
defmodule Sensocto.Encoding.DeltaEncoder do
  @moduledoc """
  Delta encoding for high-frequency ECG waveform data.

  Encodes batches of ECG samples as:
  - First value: Full float32 (4 bytes)
  - Subsequent values: int8 deltas (-128 to +127)
  - Timestamps: uint16 deltas from base timestamp (milliseconds)

  When delta exceeds int8 range, inserts a reset marker (0x80) followed
  by a new full float32 value.
  """

  # Quantization: 0.01 mV per step (ECG range -0.25 to +1.0)
  @quantization_step 0.01

  # Reset marker for overflow
  @reset_marker 0x80

  @doc "Encode a list of measurements to binary"
  def encode(measurements, opts \\ [])

  @doc "Decode binary back to measurements (for testing)"
  def decode(binary)

  @doc "Check if encoding is enabled via feature flag"
  def enabled?()
end
```

**Encoding Format**:
```
[Header: 1 byte] [Base Timestamp: 8 bytes] [First Value: 4 bytes] [Deltas...]

Header byte:
  - Bits 0-3: Version (0x01)
  - Bits 4-7: Flags (0x00 = standard, 0x01 = has resets)

Delta format:
  - Normal: [int8 value_delta] [uint16 timestamp_delta_ms]
  - Reset:  [0x80] [float32 new_value] [uint16 timestamp_delta_ms]
```

---

## Phase 2: Configuration

**Add to** `config/config.exs`:
```elixir
config :sensocto, :delta_encoding,
  enabled: false,  # Disabled by default for safety
  quantization_step: 0.01,
  supported_attributes: ["ecg"]
```

**Add to** `config/runtime.exs`:
```elixir
config :sensocto, :delta_encoding,
  enabled: System.get_env("DELTA_ENCODING_ENABLED", "false") == "true"
```

---

## Phase 3: PriorityLens Integration

**Modify** `lib/sensocto/lenses/priority_lens.ex`

In `flush_batch/3`, optionally encode ECG data:

```elixir
defp flush_batch(state, socket_id, socket_state) do
  buffer = Map.get(state.buffers, socket_id, %{})
  encoded_buffer = maybe_encode_high_frequency_data(buffer)

  if map_size(encoded_buffer) > 0 do
    Phoenix.PubSub.broadcast(
      Sensocto.PubSub,
      socket_state.topic,
      {:lens_batch, encoded_buffer}
    )
  end

  %{state | buffers: Map.put(state.buffers, socket_id, %{})}
end

defp maybe_encode_high_frequency_data(buffer) do
  if Sensocto.Encoding.DeltaEncoder.enabled?() do
    Map.new(buffer, fn {sensor_id, attributes} ->
      encoded_attrs = Map.new(attributes, fn {attr_id, data} ->
        if attr_id in @high_frequency_attributes and is_list(data) do
          {attr_id, encode_ecg_batch(data)}
        else
          {attr_id, data}
        end
      end)
      {sensor_id, encoded_attrs}
    end)
  else
    buffer  # Pass through unchanged - existing path preserved
  end
end

defp encode_ecg_batch(measurements) when is_list(measurements) do
  case Sensocto.Encoding.DeltaEncoder.encode(measurements) do
    {:ok, encoded_binary} ->
      %{
        __delta_encoded__: true,
        data: Base.encode64(encoded_binary),
        sample_count: length(measurements)
      }
    {:error, _reason} ->
      # Fallback to unencoded
      measurements
  end
end
```

---

## Phase 4: LiveView Event Handling

**Modify** `lib/sensocto_web/live/lobby_live.ex`

In `process_lens_batch_for_composite/3`:

```elixir
Enum.reduce(relevant, acc, fn {attr_id, m}, sock ->
  case m do
    # Delta-encoded ECG data - pass through as-is
    %{__delta_encoded__: true} = encoded ->
      push_event(sock, "composite_measurement_encoded", %{
        sensor_id: sensor_id,
        attribute_id: attr_id,
        encoded: encoded
      })

    # List of measurements (legacy path - unchanged)
    list when is_list(list) ->
      Enum.reduce(list, sock, fn item, inner_sock ->
        push_event(inner_sock, "composite_measurement", %{
          sensor_id: sensor_id,
          attribute_id: attr_id,
          payload: item.payload,
          timestamp: item.timestamp
        })
      end)

    # Single measurement (unchanged)
    single ->
      push_event(sock, "composite_measurement", %{
        sensor_id: sensor_id,
        attribute_id: attr_id,
        payload: single.payload,
        timestamp: single.timestamp
      })
  end
end)
```

---

## Phase 5: JavaScript Decoder

**Create** `assets/js/encoding/delta_decoder.js`

```javascript
/**
 * Delta decoder for high-frequency ECG data
 * Mirrors Elixir Sensocto.Encoding.DeltaEncoder
 */

const QUANTIZATION_STEP = 0.01;
const RESET_MARKER = 0x80;
const VERSION = 0x01;

/**
 * Decode delta-encoded ECG data
 * @param {string} base64Data - Base64 encoded binary data
 * @returns {Array<{timestamp: number, payload: number}>|null} Decoded measurements or null on failure
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

    // Read header
    const header = bytes[offset++];
    const version = header & 0x0F;
    if (version !== VERSION) {
      throw new Error(`Unsupported delta encoding version: ${version}`);
    }

    // Read base timestamp (BigInt64)
    const baseTimestamp = Number(view.getBigInt64(offset, true));
    offset += 8;

    // Read first value (Float32)
    let currentValue = view.getFloat32(offset, true);
    offset += 4;

    const measurements = [];
    let currentTimestamp = baseTimestamp;

    // First measurement
    measurements.push({
      timestamp: currentTimestamp,
      payload: currentValue
    });

    // Read deltas
    while (offset < bytes.length) {
      const valueDelta = view.getInt8(offset++);

      if (valueDelta === RESET_MARKER) {
        // Reset: read new full value
        currentValue = view.getFloat32(offset, true);
        offset += 4;
      } else {
        // Normal delta
        currentValue += valueDelta * QUANTIZATION_STEP;
      }

      // Read timestamp delta (uint16 ms)
      const timestampDelta = view.getUint16(offset, true);
      offset += 2;
      currentTimestamp += timestampDelta;

      measurements.push({
        timestamp: currentTimestamp,
        payload: currentValue
      });
    }

    return measurements;
  } catch (error) {
    console.error('[DeltaDecoder] Failed to decode:', error);
    return null;
  }
}

/**
 * Check if data is delta-encoded
 */
export function isDeltaEncoded(data) {
  return data && data.__delta_encoded__ === true;
}
```

---

## Phase 6: Update JS Event Handler

**Modify** `assets/js/app.js` (in SensorDataAccumulator hook)

```javascript
import { decodeECG, isDeltaEncoded } from './encoding/delta_decoder.js';

// Add handler for encoded measurements
this.handleEvent("composite_measurement_encoded", (event) => {
  const { sensor_id, attribute_id, encoded } = event;

  if (isDeltaEncoded(encoded)) {
    const measurements = decodeECG(encoded.data);

    if (measurements) {
      // Dispatch individual measurements for compatibility with existing Svelte components
      measurements.forEach(m => {
        const customEvent = new CustomEvent('composite-measurement-event', {
          detail: {
            sensor_id,
            attribute_id,
            payload: m.payload,
            timestamp: m.timestamp
          }
        });
        window.dispatchEvent(customEvent);
      });
    } else {
      console.warn('[SensorDataAccumulator] Delta decode failed, data dropped');
    }
  }
});

// Existing handler for non-encoded measurements (unchanged)
this.handleEvent("composite_measurement", (event) => {
  const customEvent = new CustomEvent('composite-measurement-event', {
    detail: event
  });
  window.dispatchEvent(customEvent);
});
```

---

## Phase 7: Testing

### Elixir Tests

**Create** `test/sensocto/encoding/delta_encoder_test.exs`

```elixir
defmodule Sensocto.Encoding.DeltaEncoderTest do
  use ExUnit.Case, async: true
  alias Sensocto.Encoding.DeltaEncoder

  describe "encode/1" do
    test "encodes simple ECG batch" do
      measurements = [
        %{timestamp: 1000, payload: 0.5},
        %{timestamp: 1010, payload: 0.51},
        %{timestamp: 1020, payload: 0.52}
      ]

      assert {:ok, binary} = DeltaEncoder.encode(measurements)
      assert is_binary(binary)
      assert byte_size(binary) < 50
    end

    test "handles overflow with reset marker" do
      measurements = [
        %{timestamp: 1000, payload: 0.0},
        %{timestamp: 1010, payload: 2.0}  # Delta overflow
      ]

      assert {:ok, binary} = DeltaEncoder.encode(measurements)
      assert :binary.match(binary, <<0x80>>) != :nomatch
    end

    test "round-trip preserves values within tolerance" do
      measurements = generate_ecg_samples(50)
      {:ok, encoded} = DeltaEncoder.encode(measurements)
      {:ok, decoded} = DeltaEncoder.decode(encoded)

      Enum.zip(measurements, decoded)
      |> Enum.each(fn {orig, dec} ->
        assert_in_delta orig.payload, dec.payload, 0.005
        assert orig.timestamp == dec.timestamp
      end)
    end

    test "returns error for insufficient samples" do
      assert {:error, :insufficient_samples} =
        DeltaEncoder.encode([%{timestamp: 1000, payload: 0.5}])
    end
  end
end
```

### JavaScript Tests

**Create** `assets/js/encoding/__tests__/delta_decoder.test.js`

```javascript
import { decodeECG, isDeltaEncoded } from '../delta_decoder.js';

describe('DeltaDecoder', () => {
  test('decodes simple ECG batch', () => {
    // Use pre-computed base64 from Elixir encoder
    const encoded = "..."; // Generated from Elixir tests
    const measurements = decodeECG(encoded);

    expect(measurements).toHaveLength(3);
    expect(measurements[0].payload).toBeCloseTo(0.5, 2);
  });

  test('returns null on invalid data', () => {
    expect(decodeECG("invalid!!!")).toBeNull();
    expect(decodeECG("")).toBeNull();
  });

  test('isDeltaEncoded correctly identifies encoded data', () => {
    expect(isDeltaEncoded({ __delta_encoded__: true, data: "..." })).toBe(true);
    expect(isDeltaEncoded({ payload: 0.5 })).toBe(false);
    expect(isDeltaEncoded(null)).toBe(false);
  });
});
```

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| **Precision loss** | 0.01 mV step adequate (standard ECG resolution = 0.04 mV) |
| **Delta overflow** | Reset marker mechanism, <1% frequency expected for normal ECG |
| **Error propagation** | Decoder returns null, data dropped gracefully (gap in waveform) |
| **Browser compat** | DataView/atob supported in all browsers since 2012 |
| **Debugging** | Add `DeltaEncoder.decode/1` for inspection, log in dev mode |

---

## Rollout Strategy

### Stage 1: Development Testing
- Deploy with `DELTA_ENCODING_ENABLED=false`
- Enable manually via IEx: `Application.put_env(:sensocto, :delta_encoding, enabled: true)`
- Verify waveform rendering in browser

### Stage 2: Staging
- Enable via environment variable
- Monitor logs for encoding errors
- Measure actual bandwidth reduction

### Stage 3: Production (Gradual)
- Enable for 10% → 25% → 50% → 100% of connections
- Monitor compression ratio metrics
- Watch for decode failures in browser console

### Stage 4: Default Enabled
- Flip default to `enabled: true` in config
- Keep environment variable override for emergencies

---

## Files Summary

| File | Action |
|------|--------|
| `lib/sensocto/encoding/delta_encoder.ex` | **Create** |
| `config/config.exs` | Add delta_encoding config |
| `config/runtime.exs` | Add env var support |
| `lib/sensocto/lenses/priority_lens.ex` | Modify flush_batch |
| `lib/sensocto_web/live/lobby_live.ex` | Handle encoded events |
| `assets/js/encoding/delta_decoder.js` | **Create** |
| `assets/js/app.js` | Add event handler |
| `test/sensocto/encoding/delta_encoder_test.exs` | **Create** |
| `assets/js/encoding/__tests__/delta_decoder.test.js` | **Create** |

---

## Verification Checklist

- [ ] Elixir tests pass: `mix test test/sensocto/encoding/`
- [ ] JS tests pass: `npm test -- delta_decoder`
- [ ] Enable feature flag locally
- [ ] Navigate to `/lobby` with ECG sensors
- [ ] Verify sparklines render correctly (waveform visible)
- [ ] Check Network tab for `composite_measurement_encoded` events
- [ ] Compare payload sizes before/after
- [ ] Test with feature flag disabled (existing path still works)
