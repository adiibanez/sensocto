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
      # 1 header + 8 timestamp + 4 float + 2*(1 delta + 2 ts) = 19 bytes
      assert byte_size(binary) < 50
    end

    test "handles overflow with reset marker" do
      measurements = [
        %{timestamp: 1000, payload: 0.0},
        # Delta of 2.0 / 0.01 = 200 steps, exceeds int8 range
        %{timestamp: 1010, payload: 2.0}
      ]

      assert {:ok, binary} = DeltaEncoder.encode(measurements)
      assert {:ok, decoded} = DeltaEncoder.decode(binary)
      assert length(decoded) == 2
      assert_in_delta Enum.at(decoded, 1).payload, 2.0, 0.005
    end

    test "round-trip preserves values within tolerance" do
      measurements = generate_ecg_samples(50)
      {:ok, encoded} = DeltaEncoder.encode(measurements)
      {:ok, decoded} = DeltaEncoder.decode(encoded)

      assert length(decoded) == length(measurements)

      Enum.zip(measurements, decoded)
      |> Enum.each(fn {orig, dec} ->
        assert_in_delta orig.payload, dec.payload, 0.005
        assert orig.timestamp == dec.timestamp
      end)
    end

    test "achieves significant compression vs JSON" do
      measurements = generate_ecg_samples(50)
      json_size = byte_size(Jason.encode!(measurements))
      {:ok, encoded} = DeltaEncoder.encode(measurements)
      delta_size = byte_size(encoded)

      # Should achieve at least 80% reduction
      assert delta_size / json_size < 0.2
    end

    test "returns error for insufficient samples" do
      assert {:error, :insufficient_samples} =
               DeltaEncoder.encode([%{timestamp: 1000, payload: 0.5}])

      assert {:error, :insufficient_samples} = DeltaEncoder.encode([])
    end

    test "handles negative payload values" do
      measurements = [
        %{timestamp: 1000, payload: -0.2},
        %{timestamp: 1010, payload: -0.15},
        %{timestamp: 1020, payload: -0.1}
      ]

      {:ok, encoded} = DeltaEncoder.encode(measurements)
      {:ok, decoded} = DeltaEncoder.decode(encoded)

      Enum.zip(measurements, decoded)
      |> Enum.each(fn {orig, dec} ->
        assert_in_delta orig.payload, dec.payload, 0.005
      end)
    end

    test "handles constant values (zero deltas)" do
      measurements =
        Enum.map(0..9, fn i ->
          %{timestamp: 1000 + i * 10, payload: 0.5}
        end)

      {:ok, encoded} = DeltaEncoder.encode(measurements)
      {:ok, decoded} = DeltaEncoder.decode(encoded)
      assert length(decoded) == 10

      Enum.each(decoded, fn m ->
        assert_in_delta m.payload, 0.5, 0.005
      end)
    end

    test "handles multiple resets in sequence" do
      measurements = [
        %{timestamp: 1000, payload: 0.0},
        %{timestamp: 1010, payload: 5.0},
        %{timestamp: 1020, payload: -5.0},
        %{timestamp: 1030, payload: 10.0}
      ]

      {:ok, encoded} = DeltaEncoder.encode(measurements)
      {:ok, decoded} = DeltaEncoder.decode(encoded)

      assert length(decoded) == 4

      Enum.zip(measurements, decoded)
      |> Enum.each(fn {orig, dec} ->
        assert_in_delta orig.payload, dec.payload, 0.005
        assert orig.timestamp == dec.timestamp
      end)
    end
  end

  describe "decode/1" do
    test "returns error for invalid format" do
      assert {:error, :invalid_format} = DeltaEncoder.decode(<<0xFF, 0, 0>>)
      assert {:error, :invalid_format} = DeltaEncoder.decode(<<>>)
    end

    test "returns error for truncated data" do
      # Valid header + base timestamp + first value, then a partial delta
      {:ok, valid} =
        DeltaEncoder.encode([
          %{timestamp: 1000, payload: 0.5},
          %{timestamp: 1010, payload: 0.51}
        ])

      # Truncate: keep header + base + first value but chop the delta entry
      truncated = binary_part(valid, 0, 14)
      assert {:error, :truncated} = DeltaEncoder.decode(truncated)
    end
  end

  describe "enabled?/0" do
    test "returns false by default" do
      refute DeltaEncoder.enabled?()
    end
  end

  defp generate_ecg_samples(count) do
    Enum.map(0..(count - 1), fn i ->
      %{
        timestamp: 1000 + i * 10,
        payload: 0.5 + :math.sin(i * 0.3) * 0.2
      }
    end)
  end
end
