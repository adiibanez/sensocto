defmodule SensoctoWeb.LobbyLive.Hooks.GuidedSessionHook do
  @moduledoc """
  attach_hook handler for guided session events in LobbyLive.
  Handles guidance PubSub messages for guide/follower coordination.
  """
  use SensoctoWeb, :verified_routes

  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]

  def on_handle_info({:guided_lens_changed, %{lens: lens}}, socket) do
    if socket.assigns.guided_session && socket.assigns.guided_following do
      {:halt, push_patch(socket, to: lens_to_path(lens))}
    else
      {:halt, socket}
    end
  end

  def on_handle_info({:guided_sensor_focused, %{sensor_id: sensor_id}}, socket) do
    {:halt, assign(socket, :guided_focused_sensor_id, sensor_id)}
  end

  def on_handle_info({:guided_annotation, %{annotation: annotation}}, socket) do
    annotations = socket.assigns.guided_annotations ++ [annotation]
    {:halt, assign(socket, :guided_annotations, annotations)}
  end

  def on_handle_info({:guided_suggestion, %{action: action}}, socket) do
    {:halt, assign(socket, :guided_suggestion, action)}
  end

  def on_handle_info({:guided_layout_changed, %{layout: layout}}, socket) do
    if socket.assigns.guided_session && socket.assigns.guided_following do
      {:halt,
       socket
       |> assign(:lobby_layout, layout)
       |> push_event("save_lobby_layout", %{layout: Atom.to_string(layout)})}
    else
      {:halt, socket}
    end
  end

  def on_handle_info({:guided_quality_changed, %{quality: quality}}, socket) do
    if socket.assigns.guided_session && socket.assigns.guided_following do
      socket =
        if quality == :auto do
          socket
          |> assign(:quality_override, nil)
          |> push_event("quality_changed", %{level: :auto, reason: "Guide changed"})
        else
          if socket.assigns[:priority_lens_registered] do
            Sensocto.Lenses.PriorityLens.set_quality(socket.id, quality)
          end

          socket
          |> assign(:quality_override, quality)
          |> assign(:current_quality, quality)
          |> push_event("quality_changed", %{level: quality, reason: "Guide changed"})
        end

      {:halt, socket}
    else
      {:halt, socket}
    end
  end

  def on_handle_info({:guided_sort_changed, %{sort_by: sort_by}}, socket) do
    if socket.assigns.guided_session && socket.assigns.guided_following do
      sorted =
        SensoctoWeb.LobbyLive.sort_sensors(
          socket.assigns.sensor_ids,
          socket.assigns.sensors,
          sort_by
        )

      {:halt,
       socket
       |> assign(:sort_by, sort_by)
       |> assign(:sensor_ids, sorted)
       |> push_event("save_sort_by", %{sort_by: Atom.to_string(sort_by)})}
    else
      {:halt, socket}
    end
  end

  def on_handle_info({:guided_mode_changed, %{mode: mode}}, socket) do
    if socket.assigns.guided_session && socket.assigns.guided_following do
      old_mode = socket.assigns.lobby_mode
      user = socket.assigns.current_user

      if user && old_mode != mode do
        SensoctoWeb.LobbyLive.release_control_for_mode(old_mode, user.id)
      end

      {:halt,
       socket
       |> assign(:lobby_mode, mode)
       |> push_event("save_lobby_mode", %{mode: Atom.to_string(mode)})}
    else
      {:halt, socket}
    end
  end

  def on_handle_info({:guided_panel_changed, %{panel: panel, collapsed: collapsed}}, socket) do
    if socket.assigns.guided_session && socket.assigns.guided_following do
      {:halt, assign(socket, panel, collapsed)}
    else
      {:halt, socket}
    end
  end

  def on_handle_info({:guided_break_away, _payload}, socket) do
    if socket.assigns.guiding_session do
      {:halt, assign(socket, :guided_following, false)}
    else
      {:halt, socket}
    end
  end

  def on_handle_info({:guided_drift_back, %{lens: lens} = payload}, socket) do
    socket = assign(socket, :guided_following, true)

    if socket.assigns.guided_session do
      socket =
        socket
        |> SensoctoWeb.LobbyLive.apply_guided_settings(payload)
        |> push_patch(to: lens_to_path(lens))

      {:halt, socket}
    else
      {:halt, socket}
    end
  end

  def on_handle_info({:guided_rejoin, _payload}, socket) do
    {:halt, assign(socket, :guided_following, true)}
  end

  def on_handle_info({:guided_presence, presence}, socket) do
    {:halt, assign(socket, :guided_presence, presence)}
  end

  def on_handle_info({:guided_ended, _payload}, socket) do
    {:halt,
     socket
     |> assign(:guided_session, nil)
     |> assign(:guiding_session, nil)
     |> assign(:guided_following, true)
     |> assign(:guided_annotations, [])
     |> assign(:guided_suggestion, nil)
     |> assign(:guided_focused_sensor_id, nil)
     |> assign(:guided_presence, %{guide_connected: false, follower_connected: false})
     |> put_flash(:info, "Guided session ended.")}
  end

  def on_handle_info(
        {:guidance_invitation_accepted, %{session_id: session_id, follower_name: name}},
        socket
      ) do
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "guidance:#{session_id}")
    Sensocto.Guidance.SessionServer.connect(session_id, socket.assigns.current_user.id)

    {:halt,
     socket
     |> assign(:guiding_session, session_id)
     |> assign(:guided_following, true)
     |> put_flash(:info, "#{name} joined your guided session.")}
  end

  def on_handle_info({:guidance_available, %{session_id: session_id} = info}, socket) do
    if is_nil(socket.assigns.guided_session) && is_nil(socket.assigns.guiding_session) do
      {:halt,
       assign(socket, :available_guided_session, %{
         session_id: session_id,
         guide_user_id: info.guide_user_id,
         guide_name: info.guide_name
       })}
    else
      {:halt, socket}
    end
  end

  def on_handle_info({:guidance_unavailable, %{session_id: session_id}}, socket) do
    current = socket.assigns[:available_guided_session]

    if current && current.session_id == session_id do
      {:halt, assign(socket, :available_guided_session, nil)}
    else
      {:halt, socket}
    end
  end

  def on_handle_info(_msg, socket), do: {:cont, socket}

  # Private helpers

  defp lens_to_path(:sensors), do: ~p"/lobby"
  defp lens_to_path(:heartrate), do: ~p"/lobby/heartrate"
  defp lens_to_path(:imu), do: ~p"/lobby/imu"
  defp lens_to_path(:location), do: ~p"/lobby/location"
  defp lens_to_path(:ecg), do: ~p"/lobby/ecg"
  defp lens_to_path(:battery), do: ~p"/lobby/battery"
  defp lens_to_path(:skeleton), do: ~p"/lobby/skeleton"
  defp lens_to_path(:respiration), do: ~p"/lobby/breathing"
  defp lens_to_path(:hrv), do: ~p"/lobby/hrv"
  defp lens_to_path(:gaze), do: ~p"/lobby/gaze"
  defp lens_to_path(:favorites), do: ~p"/lobby/favorites"
  defp lens_to_path(:users), do: ~p"/lobby/users"
  defp lens_to_path(:graph), do: ~p"/lobby/graph"
  defp lens_to_path(:graph3d), do: ~p"/lobby/graph3d"
  defp lens_to_path(:hierarchy), do: ~p"/lobby/hierarchy"
  defp lens_to_path(_), do: ~p"/lobby"
end
