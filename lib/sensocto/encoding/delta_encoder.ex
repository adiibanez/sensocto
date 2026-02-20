defmodule Sensocto.Encoding.DeltaEncoder do
  @moduledoc """
  Delta encoding for high-frequency ECG waveform data.

  Encodes batches of ECG samples as:
  - First value: Full float32 (4 bytes)
  - Subsequent values: int8 deltas (-128 to +127 quantization steps)
  - Timestamps: uint16 deltas from base timestamp (milliseconds)

  When delta exceeds int8 range, inserts a reset marker (0x80) followed
  by a new full float32 value.

  Binary format:
    [Header: 1 byte] [Base Timestamp: 8 bytes] [First Value: 4 bytes] [Deltas...]

    Header byte:
      Bits 0-3: Version (0x01)
      Bits 4-7: Reserved

    Delta entry:
      Normal: [int8 value_delta] [uint16 timestamp_delta_ms]
      Reset:  [0x80] [float32 new_value] [uint16 timestamp_delta_ms]
  """

  # Quantization: 0.01 mV per step (ECG resolution is typically 0.04 mV)
  @quantization_step 0.01

  # Reset marker — 0x80 is outside int8 signed range (-128..127 = 0x80..0x7F)
  # but 0x80 as signed int8 is -128. We use it as a sentinel since ECG deltas
  # rarely hit exactly -128 steps (1.28 mV jump in 10ms).
  @reset_marker -128

  @version 0x01

  @doc """
  Check if delta encoding is enabled via application config.
  """
  def enabled? do
    Application.get_env(:sensocto, :delta_encoding, [])
    |> Keyword.get(:enabled, false)
  end

  @doc """
  Returns the list of attribute IDs that support delta encoding.
  """
  def supported_attributes do
    Application.get_env(:sensocto, :delta_encoding, [])
    |> Keyword.get(:supported_attributes, ["ecg"])
  end

  @doc """
  Encode a list of measurements to a compact binary.

  Each measurement must have `:timestamp` (integer ms) and `:payload` (number).
  Returns `{:ok, binary}` or `{:error, reason}`.
  """
  def encode(measurements) when is_list(measurements) and length(measurements) >= 2 do
    [first | rest] = measurements
    base_ts = first.timestamp
    first_val = first.payload / 1

    header = <<@version::8>>
    base = <<base_ts::little-signed-integer-size(64), first_val::little-float-size(32)>>

    deltas =
      rest
      |> Enum.reduce({first_val, base_ts, <<>>}, fn m, {prev_val, prev_ts, acc} ->
        val = m.payload / 1
        ts = m.timestamp

        ts_delta = ts - prev_ts
        # Clamp timestamp delta to uint16 range
        ts_delta_clamped = min(ts_delta, 65_535) |> max(0)

        quantized_delta = round((val - prev_val) / @quantization_step)

        if quantized_delta >= -127 and quantized_delta <= 127 do
          # Normal delta (avoiding -128 which is our reset marker)
          {prev_val + quantized_delta * @quantization_step, ts,
           acc <>
             <<quantized_delta::little-signed-integer-size(8),
               ts_delta_clamped::little-unsigned-integer-size(16)>>}
        else
          # Overflow — emit reset marker + full float32
          {val, ts,
           acc <>
             <<@reset_marker::signed-integer-size(8), val::little-float-size(32),
               ts_delta_clamped::little-unsigned-integer-size(16)>>}
        end
      end)
      |> elem(2)

    {:ok, header <> base <> deltas}
  end

  def encode([_single]), do: {:error, :insufficient_samples}
  def encode([]), do: {:error, :insufficient_samples}

  @doc """
  Decode a delta-encoded binary back to a list of measurements.
  Returns `{:ok, measurements}` or `{:error, reason}`.
  """
  def decode(
        <<@version::8, base_ts::little-signed-integer-size(64), first_val::little-float-size(32),
          rest::binary>>
      ) do
    first = %{timestamp: base_ts, payload: first_val}

    case decode_deltas(rest, first_val, base_ts, []) do
      {:ok, decoded_rest} ->
        {:ok, [first | Enum.reverse(decoded_rest)]}

      error ->
        error
    end
  end

  def decode(_), do: {:error, :invalid_format}

  defp decode_deltas(<<>>, _prev_val, _prev_ts, acc), do: {:ok, acc}

  # Reset marker: next 4 bytes are a full float32
  defp decode_deltas(
         <<@reset_marker::signed-integer-size(8), val::little-float-size(32),
           ts_delta::little-unsigned-integer-size(16), rest::binary>>,
         _prev_val,
         prev_ts,
         acc
       ) do
    ts = prev_ts + ts_delta
    decode_deltas(rest, val, ts, [%{timestamp: ts, payload: val} | acc])
  end

  # Normal delta
  defp decode_deltas(
         <<delta::little-signed-integer-size(8), ts_delta::little-unsigned-integer-size(16),
           rest::binary>>,
         prev_val,
         prev_ts,
         acc
       ) do
    val = prev_val + delta * @quantization_step
    ts = prev_ts + ts_delta
    decode_deltas(rest, val, ts, [%{timestamp: ts, payload: val} | acc])
  end

  defp decode_deltas(_invalid, _prev_val, _prev_ts, _acc), do: {:error, :truncated}
end
