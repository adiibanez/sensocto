defmodule SensoctoWeb.DevicesLive do
  @moduledoc """
  My Devices page - shows user's connectors with status, sensors, and management.
  """

  use SensoctoWeb, :live_view

  alias Sensocto.Sensors.{Connector, ConnectorManager}

  on_mount {SensoctoWeb.LiveUserAuth, :ensure_authenticated}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "user:#{user.id}:connectors")
    end

    connectors = load_connectors(user.id)

    {:ok,
     assign(socket,
       page_title: "My Devices",
       connectors: connectors,
       editing_id: nil,
       edit_name: ""
     )}
  end

  @impl true
  def handle_event("start_rename", %{"id" => id}, socket) do
    connector = Enum.find(socket.assigns.connectors, &(to_string(&1.id) == id))
    name = if connector, do: connector.name, else: ""
    {:noreply, assign(socket, editing_id: id, edit_name: name)}
  end

  @impl true
  def handle_event("cancel_rename", _params, socket) do
    {:noreply, assign(socket, editing_id: nil, edit_name: "")}
  end

  @impl true
  def handle_event("save_rename", %{"name" => name}, socket) do
    id = socket.assigns.editing_id
    user = socket.assigns.current_user

    case ConnectorManager.get(id) do
      {:ok, connector} ->
        case connector
             |> Ash.Changeset.for_update(:rename, %{name: name})
             |> Ash.update(actor: user) do
          {:ok, _updated} ->
            connectors = load_connectors(user.id)
            {:noreply, assign(socket, connectors: connectors, editing_id: nil, edit_name: "")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to rename connector")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Connector not found")}
    end
  end

  @impl true
  def handle_event("forget_connector", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    case ConnectorManager.get(id) do
      {:ok, connector} ->
        case Ash.destroy(connector, action: :forget, actor: user) do
          :ok ->
            connectors = load_connectors(user.id)
            {:noreply, assign(socket, connectors: connectors)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to forget connector")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Connector not found")}
    end
  end

  @impl true
  def handle_info({:connector_event, _event, _data}, socket) do
    connectors = load_connectors(socket.assigns.current_user.id)
    {:noreply, assign(socket, connectors: connectors)}
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  defp load_connectors(user_id) do
    Connector
    |> Ash.Query.for_read(:list_for_user, %{user_id: user_id})
    |> Ash.Query.load(:sensors)
    |> Ash.read!()
    |> Enum.sort_by(& &1.last_seen_at, {:desc, DateTime})
  end

  defp status_color(:online), do: "bg-green-500"
  defp status_color(:idle), do: "bg-yellow-500"
  defp status_color(_), do: "bg-gray-500"

  defp status_text(:online), do: "Online"
  defp status_text(:idle), do: "Idle"
  defp status_text(_), do: "Offline"

  defp type_icon(:web), do: "globe-alt"
  defp type_icon(:native), do: "device-phone-mobile"
  defp type_icon(:iot), do: "cpu-chip"
  defp type_icon(:simulator), do: "beaker"
  defp type_icon(_), do: "question-mark-circle"

  defp time_ago(nil), do: "Never"

  defp time_ago(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86400)}d ago"
    end
  end
end
