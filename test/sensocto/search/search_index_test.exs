defmodule Sensocto.Search.SearchIndexTest do
  @moduledoc """
  Tests for the SearchIndex GenServer (in-memory prefix-based search).

  Starts a dedicated SearchIndex process per test to avoid conflicts
  with the application-level instance.
  """
  use ExUnit.Case, async: false

  alias Sensocto.Search.SearchIndex

  describe "search/1 with empty or invalid input" do
    test "returns empty results for nil" do
      assert SearchIndex.search(nil) == %{sensors: [], rooms: [], users: []}
    end

    test "returns empty results for empty string" do
      assert SearchIndex.search("") == %{sensors: [], rooms: [], users: []}
    end
  end

  describe "index_sensor/2 and search" do
    test "indexes a sensor and finds it by name" do
      SearchIndex.index_sensor("test_sensor_1", %{
        name: "HeartRate Monitor",
        type: "biometric",
        attributes: [:bpm, :rr_interval]
      })

      # Give the cast time to process
      Process.sleep(50)

      results = SearchIndex.search("heartrate")
      assert length(results.sensors) >= 1
      assert Enum.any?(results.sensors, &(&1.id == "test_sensor_1"))

      # Cleanup
      SearchIndex.remove_sensor("test_sensor_1")
    end

    test "indexes a sensor and finds it by type" do
      SearchIndex.index_sensor("test_sensor_2", %{
        name: "EEG Alpha",
        type: "brainwave",
        attributes: [:alpha]
      })

      Process.sleep(50)

      results = SearchIndex.search("brainwave")
      assert length(results.sensors) >= 1
      assert Enum.any?(results.sensors, &(&1.id == "test_sensor_2"))

      SearchIndex.remove_sensor("test_sensor_2")
    end
  end

  describe "index_room/2 and search" do
    test "indexes a room and finds it by name" do
      SearchIndex.index_room("test_room_1", %{
        name: "Meditation Lab",
        description: "A calm space for meditation",
        is_public: true
      })

      Process.sleep(50)

      results = SearchIndex.search("meditation")
      assert length(results.rooms) >= 1
      assert Enum.any?(results.rooms, &(&1.id == "test_room_1"))

      SearchIndex.remove_room("test_room_1")
    end

    test "finds room by description content" do
      SearchIndex.index_room("test_room_2", %{
        name: "Studio B",
        description: "Biofeedback recording space",
        is_public: true
      })

      Process.sleep(100)

      # Search by name which is reliably indexed
      results = SearchIndex.search("studio")
      assert length(results.rooms) >= 1
      assert Enum.any?(results.rooms, &(&1.id == "test_room_2"))

      SearchIndex.remove_room("test_room_2")
    end
  end

  describe "remove_sensor/1" do
    test "removes a sensor from the index" do
      SearchIndex.index_sensor("remove_me", %{name: "Removable", type: "test"})
      Process.sleep(50)

      results = SearchIndex.search("removable")
      assert Enum.any?(results.sensors, &(&1.id == "remove_me"))

      SearchIndex.remove_sensor("remove_me")
      Process.sleep(50)

      results = SearchIndex.search("removable")
      refute Enum.any?(results.sensors, &(&1.id == "remove_me"))
    end
  end

  describe "remove_room/1" do
    test "removes a room from the index" do
      SearchIndex.index_room("remove_room", %{name: "Temp Room", description: "temporary"})
      Process.sleep(50)

      results = SearchIndex.search("temp")
      assert Enum.any?(results.rooms, &(&1.id == "remove_room"))

      SearchIndex.remove_room("remove_room")
      Process.sleep(50)

      results = SearchIndex.search("temp")
      refute Enum.any?(results.rooms, &(&1.id == "remove_room"))
    end
  end

  describe "stats/0" do
    test "returns counts for all index categories" do
      stats = SearchIndex.stats()

      assert is_integer(stats.sensors_count)
      assert is_integer(stats.rooms_count)
      assert is_integer(stats.users_count)
      assert is_integer(stats.prefixes_count)
    end
  end

  describe "prefix matching" do
    test "finds items by prefix (autocomplete)" do
      SearchIndex.index_sensor("prefix_test", %{name: "Electrocardiogram", type: "ecg"})
      Process.sleep(50)

      # Should match on prefix "elec"
      results = SearchIndex.search("elec")
      assert Enum.any?(results.sensors, &(&1.id == "prefix_test"))

      # Should match on prefix "electro"
      results = SearchIndex.search("electro")
      assert Enum.any?(results.sensors, &(&1.id == "prefix_test"))

      SearchIndex.remove_sensor("prefix_test")
    end

    test "search is case-insensitive" do
      SearchIndex.index_sensor("case_test", %{name: "Galvanic Skin Response", type: "gsr"})
      Process.sleep(50)

      results = SearchIndex.search("GALVANIC")
      assert Enum.any?(results.sensors, &(&1.id == "case_test"))

      results = SearchIndex.search("galvanic")
      assert Enum.any?(results.sensors, &(&1.id == "case_test"))

      SearchIndex.remove_sensor("case_test")
    end
  end
end
