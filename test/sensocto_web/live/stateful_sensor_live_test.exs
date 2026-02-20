defmodule SensoctoWeb.StatefulSensorLiveTest do
  use SensoctoWeb.ConnCase

  import Phoenix.LiveViewTest

  @moduletag :integration

  describe "StatefulSensorLive" do
    setup %{conn: conn} do
      # Create a test sensor using the DynamicSupervisor
      sensor_id = "test_sensor_#{System.unique_integer([:positive])}"

      sensor_params = %{
        sensor_id: sensor_id,
        sensor_name: "Test Live Sensor",
        sensor_type: "test_type",
        connector_id: "test_connector",
        connector_name: "Test Connector",
        batch_size: 10,
        sampling_rate: 100,
        attributes: %{
          "temperature" => %{
            attribute_id: "temperature",
            attribute_type: "numeric",
            sampling_rate: 100
          }
        }
      }

      # Start the sensor
      {:ok, _pid} = Sensocto.SensorsDynamicSupervisor.add_sensor(sensor_id, sensor_params)

      # Create a test user
      email = "test_#{System.unique_integer([:positive])}@example.com"

      user =
        Ash.Seed.seed!(Sensocto.Accounts.User, %{
          email: email,
          confirmed_at: DateTime.utc_now()
        })

      # Generate a token for the user
      {:ok, token, _claims} =
        AshAuthentication.Jwt.token_for_user(user, %{purpose: :user}, token_lifetime: {1, :hours})

      # Add token to user metadata for session storage
      user = Map.put(user, :__metadata__, %{token: token})

      conn = log_in_user(conn, user)

      on_exit(fn ->
        # Clean up the sensor
        Sensocto.SensorsDynamicSupervisor.remove_sensor(sensor_id)
      end)

      {:ok, conn: conn, user: user, sensor_id: sensor_id}
    end

    test "renders sensor when provided via session", %{conn: conn, sensor_id: sensor_id} do
      {:ok, _view, html} =
        live_isolated(conn, SensoctoWeb.StatefulSensorLive,
          session: %{
            "parent_pid" => self(),
            "sensor_id" => sensor_id
          },
          layout: false
        )

      # The view should render with sensor data
      assert html =~ sensor_id or html =~ "Test Live Sensor"
    end

    test "handles view_enter event", %{conn: conn, sensor_id: sensor_id} do
      {:ok, view, _html} =
        live_isolated(conn, SensoctoWeb.StatefulSensorLive,
          session: %{
            "parent_pid" => self(),
            "sensor_id" => sensor_id
          },
          layout: false
        )

      # Send view_enter event (simulating user scrolling sensor into view)
      # The AttentionTracker hook is on #sensor_content_#{sensor_id}
      result =
        view
        |> element("#sensor_content_#{sensor_id}")
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
