defmodule Sensocto.LiveDashboard.SensorsPage do
  @moduledoc false
  use Phoenix.LiveDashboard.PageBuilder

  @impl true
  def menu_link(_, _) do
    {:ok, "Sensors"}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.live_table
      id="sensors-table"
      dom_id="sensors-table"
      page={@page}
      title="Sensors"
      row_fetcher={&fetch_ets/2}
      row_attrs={&row_attrs/1}
      rows_name="tables"
    >
      <:col field={:name} header="Name or Sensor" />
      <:col field={:id} header="Id" sortable={:asc} />
      <:col field={:type} header="Type" />
    </.live_table>
    """
  end

  defp fetch_ets(params, _node) do
    %{search: _search, sort_by: _sort_by, sort_dir: _sort_dir, limit: _limit} = params

    sensors = Sensocto.SensorsDynamicSupervisor.get_all_sensors_state()

    sensors_view_data =
      Enum.map(sensors, fn {_sensor_id, sensor} ->
        %{
          name: sensor.metadata[:sensor_name],
          id: sensor.metadata[:sensor_id],
          type: sensor.metadata[:sensor_type]
        }
      end)

    # Here goes the code that goes through all ETS tables, searches
    # (if not nil), sorts, and limits them.
    #
    # It must return a tuple where the first element is list with
    # the current entries (up to limit) and an integer with the
    # total amount of entries.
    # ...
    {sensors_view_data, Enum.count(sensors_view_data)}
    # {[], 0}
  end

  defp row_attrs(table) do
    [
      {"phx-click", "show_info"},
      {"phx-value-info", table[:id]},
      {"phx-page-loading", true}
    ]
  end
end
