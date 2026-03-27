defmodule SensoctoWeb.MidiOutputRegressionTest do
  @moduledoc """
  Regression tests for MIDI/graph data flow.

  After the ViewerDataChannel migration, composite_measurement events are
  dispatched as JS CustomEvents by the CompositeMeasurementHandler hook —
  no longer as LiveView push_events. These tests verify:
  - LobbyLive handles :lens_batch without crashing in graph view
  - midi_toggled hook events are accepted without errors
  - Graph view mounts successfully and renders expected content
  """

  use SensoctoWeb.ConnCase

  import Phoenix.LiveViewTest

  @moduletag :integration

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

  describe "graph view lens_batch handling" do
    test "handles lens_batch with single map measurement without crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/lobby/graph")

      batch = %{
        "sensor-1" => %{
          "heartrate" => %{payload: 72, timestamp: 1_234_567_890}
        }
      }

      send(view.pid, {:lens_batch, batch})

      # View should still be alive and rendering
      assert render(view) =~ "LobbyGraph"
    end

    test "handles lens_batch with list-of-maps measurement without crash", %{conn: conn} do
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

      assert render(view) =~ "LobbyGraph"
    end

    test "handles lens_batch with multiple sensors without crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/lobby/graph")

      batch = %{
        "sensor-1" => %{"heartrate" => %{payload: 72, timestamp: 1_000}},
        "sensor-2" => %{"heartrate" => %{payload: 80, timestamp: 1_001}}
      }

      send(view.pid, {:lens_batch, batch})

      assert render(view) =~ "LobbyGraph"
    end

    test "handles lens_batch with mixed attribute types without crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/lobby/graph")

      batch = %{
        "sensor-1" => %{
          "heartrate" => %{payload: 72, timestamp: 1_000},
          "battery" => %{payload: 85, timestamp: 1_000},
          "imu" => %{payload: %{x: 1, y: 2, z: 3}, timestamp: 1_000}
        }
      }

      send(view.pid, {:lens_batch, batch})

      assert render(view) =~ "LobbyGraph"
    end
  end

  describe "sensors view lens_batch handling" do
    test "handles lens_batch in sensors view without crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/lobby")

      batch = %{
        "sensor-1" => %{
          "heartrate" => %{payload: 72, timestamp: 1_000}
        }
      }

      send(view.pid, {:lens_batch, batch})

      # Sensors view should still be alive
      assert render(view) =~ "lobby"
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
