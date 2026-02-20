defmodule Sensocto.Sensors.SensorTest do
  use Sensocto.DataCase, async: true

  alias Sensocto.Sensors.Sensor

  describe "create action (default wildcard)" do
    test "creates sensor with valid attributes" do
      assert {:ok, sensor} =
               Sensor
               |> Ash.Changeset.for_create(:create, %{name: "Test Sensor"})
               |> Ash.create()

      assert sensor.name == "Test Sensor"
      assert sensor.id != nil
    end

    test "fails without name" do
      assert {:error, _} =
               Sensor
               |> Ash.Changeset.for_create(:create, %{})
               |> Ash.create()
    end

    test "creates with optional attributes" do
      assert {:ok, sensor} =
               Sensor
               |> Ash.Changeset.for_create(:create, %{
                 name: "Full Sensor",
                 mac_address: "AA:BB:CC:DD:EE:FF",
                 configuration: %{"sample_rate" => 100}
               })
               |> Ash.create()

      assert sensor.mac_address == "AA:BB:CC:DD:EE:FF"
      assert sensor.configuration == %{"sample_rate" => 100}
    end
  end

  describe "simple action (upsert)" do
    test "creates sensor with just name" do
      assert {:ok, sensor} =
               Sensor
               |> Ash.Changeset.for_create(:simple, %{name: "Simple Sensor"})
               |> Ash.create()

      assert sensor.name == "Simple Sensor"
    end
  end

  describe "update action (default wildcard)" do
    test "updates the sensor name" do
      {:ok, sensor} =
        Sensor
        |> Ash.Changeset.for_create(:create, %{name: "Old Name"})
        |> Ash.create()

      {:ok, updated} =
        sensor
        |> Ash.Changeset.for_update(:update, %{name: "New Name"})
        |> Ash.update()

      assert updated.name == "New Name"
    end

    test "updates optional attributes" do
      {:ok, sensor} =
        Sensor
        |> Ash.Changeset.for_create(:create, %{name: "Sensor"})
        |> Ash.create()

      {:ok, updated} =
        sensor
        |> Ash.Changeset.for_update(:update, %{
          mac_address: "11:22:33:44:55:66",
          configuration: %{"threshold" => 50}
        })
        |> Ash.update()

      assert updated.mac_address == "11:22:33:44:55:66"
      assert updated.configuration == %{"threshold" => 50}
    end
  end

  describe "read and destroy" do
    test "reads sensors" do
      {:ok, _} =
        Sensor
        |> Ash.Changeset.for_create(:create, %{name: "Readable Sensor"})
        |> Ash.create()

      {:ok, sensors} = Ash.read(Sensor)
      assert length(sensors) >= 1
    end

    test "destroys a sensor" do
      {:ok, sensor} =
        Sensor
        |> Ash.Changeset.for_create(:create, %{name: "To Delete"})
        |> Ash.create()

      assert :ok = Ash.destroy(sensor)

      {:ok, sensors} = Ash.read(Sensor)
      refute Enum.any?(sensors, &(&1.id == sensor.id))
    end
  end

  describe "identity" do
    test "id is unique" do
      {:ok, sensor} =
        Sensor
        |> Ash.Changeset.for_create(:create, %{name: "Unique Sensor"})
        |> Ash.create()

      # Two sensors can exist with different ids (uuid_primary_key auto-generates)
      {:ok, sensor2} =
        Sensor
        |> Ash.Changeset.for_create(:create, %{name: "Another Sensor"})
        |> Ash.create()

      assert sensor.id != sensor2.id
    end
  end
end
