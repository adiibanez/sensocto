defmodule Sensocto.Types.SafeKeysTest do
  @moduledoc """
  Tests for SafeKeys — the security boundary for all WebSocket input.
  Pure functions, zero infrastructure.
  """
  use ExUnit.Case, async: true

  alias Sensocto.Types.SafeKeys

  # ── validate_attribute_id/1 ───────────────────────────────────────

  describe "validate_attribute_id/1" do
    test "accepts valid snake_case ids" do
      assert {:ok, "heart_rate"} = SafeKeys.validate_attribute_id("heart_rate")
      assert {:ok, "bpm"} = SafeKeys.validate_attribute_id("bpm")
    end

    test "accepts Bluetooth GATT UUIDs" do
      assert {:ok, "00002a37-0000-1000-8000-00805f9b34fb"} =
               SafeKeys.validate_attribute_id("00002a37-0000-1000-8000-00805f9b34fb")
    end

    test "accepts alphanumeric start" do
      assert {:ok, "1temperature"} = SafeKeys.validate_attribute_id("1temperature")
    end

    test "rejects empty string" do
      assert {:error, :invalid_attribute_id} = SafeKeys.validate_attribute_id("")
    end

    test "rejects strings over 64 chars" do
      long = String.duplicate("a", 65)
      assert {:error, :invalid_attribute_id} = SafeKeys.validate_attribute_id(long)
    end

    test "accepts exactly 64 chars" do
      exact = String.duplicate("a", 64)
      assert {:ok, ^exact} = SafeKeys.validate_attribute_id(exact)
    end

    test "rejects special characters" do
      assert {:error, :invalid_attribute_id} = SafeKeys.validate_attribute_id("heart rate")
      assert {:error, :invalid_attribute_id} = SafeKeys.validate_attribute_id("bpm!")
      assert {:error, :invalid_attribute_id} = SafeKeys.validate_attribute_id("a.b")
    end

    test "rejects non-binary input" do
      assert {:error, :invalid_attribute_id} = SafeKeys.validate_attribute_id(123)
      assert {:error, :invalid_attribute_id} = SafeKeys.validate_attribute_id(nil)
      assert {:error, :invalid_attribute_id} = SafeKeys.validate_attribute_id(:atom)
    end

    test "rejects strings starting with underscore or hyphen" do
      assert {:error, :invalid_attribute_id} = SafeKeys.validate_attribute_id("_private")
      assert {:error, :invalid_attribute_id} = SafeKeys.validate_attribute_id("-dashed")
    end
  end

  # ── allowed_attribute_type?/1 ─────────────────────────────────────

  describe "allowed_attribute_type?/1" do
    test "returns true for known types" do
      assert SafeKeys.allowed_attribute_type?("ecg")
      assert SafeKeys.allowed_attribute_type?("heartrate")
      assert SafeKeys.allowed_attribute_type?("battery")
      assert SafeKeys.allowed_attribute_type?("imu")
      assert SafeKeys.allowed_attribute_type?("respiration")
    end

    test "is case-insensitive" do
      assert SafeKeys.allowed_attribute_type?("ECG")
      assert SafeKeys.allowed_attribute_type?("HeartRate")
    end

    test "rejects unknown types" do
      refute SafeKeys.allowed_attribute_type?("malicious_type")
      refute SafeKeys.allowed_attribute_type?("custom_sensor")
    end
  end

  # ── validate_action/1 ─────────────────────────────────────────────

  describe "validate_action/1" do
    test "accepts register" do
      assert {:ok, "register"} = SafeKeys.validate_action("register")
    end

    test "accepts unregister" do
      assert {:ok, "unregister"} = SafeKeys.validate_action("unregister")
    end

    test "rejects unknown actions" do
      assert {:error, :invalid_action} = SafeKeys.validate_action("delete")
      assert {:error, :invalid_action} = SafeKeys.validate_action("hack")
      assert {:error, :invalid_action} = SafeKeys.validate_action("")
    end

    test "rejects non-string input" do
      assert {:error, :invalid_action} = SafeKeys.validate_action(nil)
      assert {:error, :invalid_action} = SafeKeys.validate_action(:register)
    end
  end

  # ── safe_string_to_existing_atom/1 ────────────────────────────────

  describe "safe_string_to_existing_atom/1" do
    test "converts whitelisted keys to atoms" do
      assert {:ok, :sensor_id} = SafeKeys.safe_string_to_existing_atom("sensor_id")
      assert {:ok, :payload} = SafeKeys.safe_string_to_existing_atom("payload")
      assert {:ok, :timestamp} = SafeKeys.safe_string_to_existing_atom("timestamp")
    end

    test "keeps unknown keys as strings" do
      assert {:ok, "unknown_key"} = SafeKeys.safe_string_to_existing_atom("unknown_key")
      assert {:ok, "malicious"} = SafeKeys.safe_string_to_existing_atom("malicious")
    end

    test "passes through atoms unchanged" do
      assert {:ok, :already_atom} = SafeKeys.safe_string_to_existing_atom(:already_atom)
    end
  end

  # ── safe_keys_to_atoms/1 ──────────────────────────────────────────

  describe "safe_keys_to_atoms/1" do
    test "converts whitelisted keys, keeps unknowns as strings" do
      input = %{"sensor_id" => "abc", "custom_field" => 123}
      assert {:ok, result} = SafeKeys.safe_keys_to_atoms(input)

      assert result[:sensor_id] == "abc"
      assert result["custom_field"] == 123
    end

    test "recursively converts nested maps" do
      input = %{"payload" => %{"bpm" => 72, "unknown" => true}}
      assert {:ok, result} = SafeKeys.safe_keys_to_atoms(input)

      assert result[:payload][:bpm] == 72
      assert result[:payload]["unknown"] == true
    end

    test "handles empty map" do
      assert {:ok, %{}} = SafeKeys.safe_keys_to_atoms(%{})
    end
  end

  # ── validate_measurement_keys/1 ───────────────────────────────────

  describe "validate_measurement_keys/1" do
    test "accepts valid measurement map" do
      input = %{
        "attribute_id" => "heart_rate",
        "payload" => %{"bpm" => 72},
        "timestamp" => 1_234_567_890
      }

      assert {:ok, ^input} = SafeKeys.validate_measurement_keys(input)
    end

    test "rejects missing attribute_id" do
      assert {:error, {:missing_fields, missing}} =
               SafeKeys.validate_measurement_keys(%{
                 "payload" => %{},
                 "timestamp" => 123
               })

      assert "attribute_id" in missing
    end

    test "rejects missing payload" do
      assert {:error, {:missing_fields, missing}} =
               SafeKeys.validate_measurement_keys(%{
                 "attribute_id" => "bpm",
                 "timestamp" => 123
               })

      assert "payload" in missing
    end

    test "rejects missing timestamp" do
      assert {:error, {:missing_fields, missing}} =
               SafeKeys.validate_measurement_keys(%{
                 "attribute_id" => "bpm",
                 "payload" => %{}
               })

      assert "timestamp" in missing
    end

    test "reports all missing fields at once" do
      assert {:error, {:missing_fields, missing}} =
               SafeKeys.validate_measurement_keys(%{})

      assert length(missing) == 3
    end

    test "rejects invalid attribute_id format" do
      assert {:error, :invalid_attribute_id} =
               SafeKeys.validate_measurement_keys(%{
                 "attribute_id" => "",
                 "payload" => %{},
                 "timestamp" => 123
               })
    end
  end

  # ── safe_bridge_atom/1 ────────────────────────────────────────────

  describe "safe_bridge_atom/1" do
    test "converts whitelisted bridge atoms" do
      assert {:ok, :ok} = SafeKeys.safe_bridge_atom("ok")
      assert {:ok, :error} = SafeKeys.safe_bridge_atom("error")
      assert {:ok, :payload} = SafeKeys.safe_bridge_atom("payload")
    end

    test "rejects unknown strings" do
      assert {:error, :unknown_atom} = SafeKeys.safe_bridge_atom("malicious")
      assert {:error, :unknown_atom} = SafeKeys.safe_bridge_atom("drop_table")
    end
  end

  # ── allowed_attribute_types/0 & allowed_bridge_atoms/0 ────────────

  describe "list accessors" do
    test "allowed_attribute_types returns a non-empty list" do
      types = SafeKeys.allowed_attribute_types()
      assert is_list(types)
      assert length(types) > 0
      assert "ecg" in types
    end

    test "allowed_bridge_atoms returns a non-empty list" do
      atoms = SafeKeys.allowed_bridge_atoms()
      assert is_list(atoms)
      assert "ok" in atoms
    end
  end
end
