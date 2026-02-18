defmodule SensoctoWeb.MidiOutputRegressionTest do
  @moduledoc """
  Regression tests for MIDI output data flow.

  Guards against:
  - composite_measurement push_events not being emitted on /lobby/graph
  - MIDI-relevant attributes being dropped or misformatted
  - Non-MIDI attributes leaking into composite_measurement events
  - Measurement format handling (single map vs list of maps)
  """

  use SensoctoWeb.ConnCase

  import Phoenix.LiveViewTest

  @moduletag :integration

  @midi_attributes ["respiration", "hrv", "breathing_sync", "hrv_sync", "heartrate", "hr"]

  setup %{conn: conn} do
    email = "midi_test_#{System.unique_integer([:positive])}@example.com"

    user =
      Ash.Seed.seed!(Sensocto.Accounts.User, %{
        email: email,
        confirmed_at: DateTime.utc_now()
      })

    {:ok, token, _claims} =
      AshAuthentication.Jwt.token_for_user(user, %{purpose: :user}, token_lifetime: {1, :hours})

    user = Map.put(user, :__metadata__, %{token: token})

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> AshAuthentication.Plug.Helpers.store_in_session(user)

    {:ok, conn: conn, user: user}
  end

  describe "graph view composite_measurement push_events" do
    test "pushes composite_measurement for heartrate (single map)", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/lobby/graph")

      batch = %{
        "sensor-1" => %{
          "heartrate" => %{payload: 72, timestamp: 1_234_567_890}
        }
      }

      send(view.pid, {:lens_batch, batch})

      assert_push_event(view, "composite_measurement", %{
        sensor_id: "sensor-1",
        attribute_id: "heartrate",
        payload: 72,
        timestamp: 1_234_567_890
      })
    end

    test "pushes composite_measurement for respiration (list of maps)", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/lobby/graph")

      batch = %{
        "sensor-1" => %{
          "respiration" => [
            %{payload: 85.5, timestamp: 1_234_567_890},
            %{payload: 86.0, timestamp: 1_234_567_891}
          ]
        }
      }

      send(view.pid, {:lens_batch, batch})

      assert_push_event(view, "composite_measurement", %{
        sensor_id: "sensor-1",
        attribute_id: "respiration",
        payload: 85.5,
        timestamp: 1_234_567_890
      })

      assert_push_event(view, "composite_measurement", %{
        sensor_id: "sensor-1",
        attribute_id: "respiration",
        payload: 86.0,
        timestamp: 1_234_567_891
      })
    end

    test "pushes composite_measurement for all MIDI attribute types", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/lobby/graph")

      ts = System.system_time(:millisecond)

      batch = %{
        "sensor-1" =>
          Map.new(@midi_attributes, fn attr ->
            {attr, %{payload: 50.0, timestamp: ts}}
          end)
      }

      send(view.pid, {:lens_batch, batch})

      for attr <- @midi_attributes do
        assert_push_event(view, "composite_measurement", %{
          sensor_id: "sensor-1",
          attribute_id: ^attr
        })
      end
    end

    test "does NOT push composite_measurement for non-MIDI attributes", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/lobby/graph")

      batch = %{
        "sensor-1" => %{
          "battery" => %{payload: 85, timestamp: 1_234_567_890},
          "temperature" => %{payload: 22.5, timestamp: 1_234_567_890},
          "imu" => %{payload: %{x: 1, y: 2, z: 3}, timestamp: 1_234_567_890}
        }
      }

      send(view.pid, {:lens_batch, batch})

      # graph_activity should still be pushed (it's always pushed for graph view)
      assert_push_event(view, "graph_activity", %{sensor_id: "sensor-1"})

      # But no composite_measurement should be pushed for non-MIDI attributes
      refute_push_event(view, "composite_measurement", %{attribute_id: "battery"})
      refute_push_event(view, "composite_measurement", %{attribute_id: "temperature"})
      refute_push_event(view, "composite_measurement", %{attribute_id: "imu"})
    end

    test "pushes graph_activity alongside composite_measurement", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/lobby/graph")

      batch = %{
        "sensor-1" => %{
          "heartrate" => %{payload: 72, timestamp: 1_234_567_890}
        }
      }

      send(view.pid, {:lens_batch, batch})

      # Both events should be pushed
      assert_push_event(view, "graph_activity", %{sensor_id: "sensor-1"})
      assert_push_event(view, "composite_measurement", %{sensor_id: "sensor-1"})
    end

    test "handles multiple sensors in a single batch", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/lobby/graph")

      batch = %{
        "sensor-1" => %{"heartrate" => %{payload: 72, timestamp: 1_000}},
        "sensor-2" => %{"heartrate" => %{payload: 80, timestamp: 1_001}}
      }

      send(view.pid, {:lens_batch, batch})

      assert_push_event(view, "composite_measurement", %{sensor_id: "sensor-1", payload: 72})
      assert_push_event(view, "composite_measurement", %{sensor_id: "sensor-2", payload: 80})
    end

    test "handles mixed MIDI and non-MIDI attributes in same sensor", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/lobby/graph")

      batch = %{
        "sensor-1" => %{
          "heartrate" => %{payload: 72, timestamp: 1_000},
          "battery" => %{payload: 85, timestamp: 1_000}
        }
      }

      send(view.pid, {:lens_batch, batch})

      assert_push_event(view, "composite_measurement", %{
        attribute_id: "heartrate",
        payload: 72
      })

      refute_push_event(view, "composite_measurement", %{attribute_id: "battery"})
    end
  end

  describe "non-graph views do NOT push composite_measurement for graph data" do
    test "sensors view does not push composite_measurement", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/lobby")

      batch = %{
        "sensor-1" => %{
          "heartrate" => %{payload: 72, timestamp: 1_000}
        }
      }

      send(view.pid, {:lens_batch, batch})

      refute_push_event(view, "composite_measurement", %{attribute_id: "heartrate"}, 200)
    end
  end

  describe "midi_toggled event" do
    test "accepts midi_toggled enable event without crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/lobby/graph")

      # Should not crash
      render_hook(view, "midi_toggled", %{"enabled" => true})
      assert render(view) =~ "LobbyGraph"
    end

    test "accepts midi_toggled disable event without crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/lobby/graph")

      render_hook(view, "midi_toggled", %{"enabled" => true})
      render_hook(view, "midi_toggled", %{"enabled" => false})
      assert render(view) =~ "LobbyGraph"
    end
  end
end
