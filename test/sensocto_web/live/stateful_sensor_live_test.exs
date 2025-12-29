defmodule SensoctoWeb.StatefulSensorLiveTest do
  use SensoctoWeb.ConnCase

  import Phoenix.LiveViewTest

  @moduletag :integration

  describe "StatefulSensorLive" do
    setup %{conn: conn} do
      # Create a test user for authentication
      user =
        Sensocto.Accounts.User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "test_#{System.unique_integer([:positive])}@example.com",
          password: "password123!",
          password_confirmation: "password123!"
        })
        |> Ash.create!()

      conn = log_in_user(conn, user)

      {:ok, conn: conn, user: user}
    end

    test "renders sensor when provided via session", %{conn: conn} do
      sensor_id = "test_live_#{System.unique_integer([:positive])}"

      sensor_data = %{
        sensor_id: sensor_id,
        sensor_name: "Test Live Sensor",
        sensor_type: "test_type",
        connector_id: "test_connector",
        connector_name: "Test Connector",
        batch_size: 10,
        sampling_rate: 100,
        attributes: %{
          "temperature" => %{
            values: [23.5],
            lastvalue: 23.5,
            attribute_id: "temperature",
            attribute_type: :numeric,
            sampling_rate: 100
          }
        }
      }

      {:ok, view, html} =
        live_isolated(conn, SensoctoWeb.StatefulSensorLive,
          session: %{
            "parent_pid" => self(),
            "sensor" => sensor_data
          }
        )

      # The view should render with sensor data
      assert html =~ sensor_id or html =~ "Test Live Sensor"
    end

    test "handles view_enter event", %{conn: conn} do
      sensor_id = "test_event_#{System.unique_integer([:positive])}"

      sensor_data = %{
        sensor_id: sensor_id,
        sensor_name: "Event Test Sensor",
        sensor_type: "test_type",
        connector_id: "test_connector",
        connector_name: "Test",
        batch_size: 10,
        sampling_rate: 100,
        attributes: %{
          "temperature" => %{
            values: [25.0],
            lastvalue: 25.0,
            attribute_id: "temperature",
            attribute_type: :numeric,
            sampling_rate: 100
          }
        }
      }

      {:ok, view, _html} =
        live_isolated(conn, SensoctoWeb.StatefulSensorLive,
          session: %{
            "parent_pid" => self(),
            "sensor" => sensor_data
          }
        )

      # Send view_enter event (simulating user scrolling sensor into view)
      result =
        view
        |> element("#sensor-container-#{sensor_id}", "")
        |> render_hook("view_enter", %{
          "sensor_id" => sensor_id,
          "attribute_id" => "temperature"
        })

      # Should not crash
      assert is_binary(result) or result == :ok
    end
  end

  # Helper to log in user for tests
  defp log_in_user(conn, user) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> AshAuthentication.Plug.Helpers.store_in_session(user)
  end
end
