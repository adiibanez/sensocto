defmodule Sensocto.Object3D.Object3DPlayerServer do
  @moduledoc """
  GenServer managing synchronized 3D object viewing state for a room or lobby.
  Coordinates current object, camera position, and control across all connected clients.
  """
  use GenServer
  require Logger

  alias Sensocto.Object3D

  # Heartbeat interval for periodic sync broadcasts
  @heartbeat_interval_ms 1_000

  # Timeout for control request (30 seconds)
  @control_request_timeout_ms 30_000

  defstruct [
    :room_id,
    :playlist_id,
    :current_item_id,
    :controller_user_id,
    :controller_user_name,
    # Pending control request
    :pending_request_user_id,
    :pending_request_user_name,
    :pending_request_timer_ref,
    camera_position: %{x: 0, y: 0, z: 5},
    camera_target: %{x: 0, y: 0, z: 0},
    camera_updated_at: nil,
    is_lobby: false
  ]

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts) do
    room_id = Keyword.fetch!(opts, :room_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(room_id))
  end

  def via_tuple(room_id) do
    {:via, Registry, {Sensocto.Object3DRegistry, room_id}}
  end

  @doc """
  Gets the current player state.
  """
  def get_state(room_id) do
    GenServer.call(via_tuple(room_id), :get_state)
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc """
  Views a specific item from the playlist.
  """
  def view_item(room_id, item_id, user_id \\ nil) do
    GenServer.call(via_tuple(room_id), {:view_item, item_id, user_id})
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc """
  Skips to the next item in the playlist.
  """
  def next(room_id, user_id \\ nil) do
    GenServer.call(via_tuple(room_id), {:next, user_id})
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc """
  Goes back to the previous item in the playlist.
  """
  def previous(room_id, user_id \\ nil) do
    GenServer.call(via_tuple(room_id), {:previous, user_id})
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc """
  Takes control of the 3D viewer.
  """
  def take_control(room_id, user_id, user_name) do
    GenServer.call(via_tuple(room_id), {:take_control, user_id, user_name})
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc """
  Releases control of the 3D viewer.
  """
  def release_control(room_id, user_id) do
    GenServer.call(via_tuple(room_id), {:release_control, user_id})
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc """
  Syncs camera position from the controller.
  """
  def sync_camera(room_id, position, target, user_id) do
    GenServer.cast(via_tuple(room_id), {:sync_camera, position, target, user_id})
  end

  @doc """
  Requests control from the current controller.
  Starts a 30-second timer after which control auto-transfers unless controller keeps control.
  """
  def request_control(room_id, user_id, user_name) do
    GenServer.call(via_tuple(room_id), {:request_control, user_id, user_name})
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc """
  Controller keeps control, canceling pending request.
  """
  def keep_control(room_id, user_id) do
    GenServer.call(via_tuple(room_id), {:keep_control, user_id})
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc """
  Notifies the server that an item was added to the playlist.
  If there's no current item, auto-selects the new item.
  """
  def item_added(room_id, item) do
    GenServer.cast(via_tuple(room_id), {:item_added, item})
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    room_id = Keyword.fetch!(opts, :room_id)
    is_lobby = Keyword.get(opts, :is_lobby, false)

    Logger.info(
      "Starting Object3DPlayerServer for #{if is_lobby, do: "lobby", else: "room #{room_id}"}"
    )

    # Get or create the playlist
    playlist_result =
      if is_lobby do
        Object3D.get_or_create_lobby_playlist()
      else
        Object3D.get_or_create_room_playlist(room_id)
      end

    case playlist_result do
      {:ok, playlist} ->
        # Get the first item if any
        first_item = Object3D.get_first_item(playlist.id)

        state = %__MODULE__{
          room_id: room_id,
          playlist_id: playlist.id,
          current_item_id: first_item && first_item.id,
          is_lobby: is_lobby,
          camera_position: %{x: 0, y: 0, z: 5},
          camera_target: %{x: 0, y: 0, z: 0},
          camera_updated_at: DateTime.utc_now()
        }

        # Start periodic heartbeat for sync
        schedule_heartbeat()

        {:ok, state}

      {:error, reason} ->
        Logger.error("Failed to create 3D object playlist: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  defp schedule_heartbeat do
    Process.send_after(self(), :heartbeat, @heartbeat_interval_ms)
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    playlist_items = Object3D.get_playlist_items(state.playlist_id)

    # If no current item but playlist has items, auto-select the first one
    {current_item, state} =
      case {state.current_item_id, playlist_items} do
        {nil, [first | _]} ->
          Logger.info("Auto-selecting first 3D object #{first.id} on get_state")
          new_state = %{state | current_item_id: first.id}
          {first, new_state}

        {item_id, _} when not is_nil(item_id) ->
          {Object3D.get_item(item_id), state}

        _ ->
          {nil, state}
      end

    response = %{
      current_item: current_item,
      playlist_items: playlist_items,
      controller_user_id: state.controller_user_id,
      controller_user_name: state.controller_user_name,
      camera_position: state.camera_position,
      camera_target: state.camera_target
    }

    {:reply, {:ok, response}, state}
  end

  @impl true
  def handle_call({:view_item, item_id, user_id}, _from, state) do
    if can_control?(state, user_id) do
      do_view_item(state, item_id)
    else
      {:reply, {:error, :not_controller}, state}
    end
  end

  @impl true
  def handle_call({:next, user_id}, _from, state) do
    if can_control?(state, user_id) do
      do_next(state)
    else
      {:reply, {:error, :not_controller}, state}
    end
  end

  @impl true
  def handle_call({:previous, user_id}, _from, state) do
    if can_control?(state, user_id) do
      do_previous(state)
    else
      {:reply, {:error, :not_controller}, state}
    end
  end

  @impl true
  def handle_call({:take_control, user_id, user_name}, _from, state) do
    new_state = %{
      state
      | controller_user_id: user_id,
        controller_user_name: user_name
    }

    broadcast_controller_change(new_state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:release_control, user_id}, _from, state) do
    if state.controller_user_id == user_id do
      # Cancel any pending request timer
      state = cancel_pending_request(state)

      new_state = %{
        state
        | controller_user_id: nil,
          controller_user_name: nil
      }

      broadcast_controller_change(new_state)
      {:reply, :ok, new_state}
    else
      {:reply, {:error, :not_controller}, state}
    end
  end

  @impl true
  def handle_call({:request_control, user_id, user_name}, _from, state) do
    cond do
      # No controller - just take control directly
      is_nil(state.controller_user_id) ->
        new_state = %{
          state
          | controller_user_id: user_id,
            controller_user_name: user_name
        }

        broadcast_controller_change(new_state)
        {:reply, {:ok, :control_granted}, new_state}

      # Already the controller
      state.controller_user_id == user_id ->
        {:reply, {:ok, :already_controller}, state}

      # Someone else is controller - start pending request with timer
      true ->
        # Cancel any existing pending request
        state = cancel_pending_request(state)

        # Start timeout timer
        timer_ref =
          Process.send_after(
            self(),
            {:control_request_timeout, user_id},
            @control_request_timeout_ms
          )

        new_state = %{
          state
          | pending_request_user_id: user_id,
            pending_request_user_name: user_name,
            pending_request_timer_ref: timer_ref
        }

        # Broadcast to notify controller of pending request
        broadcast_control_request(new_state, user_id, user_name)
        {:reply, {:ok, :request_pending}, new_state}
    end
  end

  @impl true
  def handle_call({:keep_control, user_id}, _from, state) do
    if state.controller_user_id == user_id and state.pending_request_user_id do
      # Cancel the pending request
      new_state = cancel_pending_request(state)
      broadcast_control_request_denied(new_state, state.pending_request_user_id)
      {:reply, :ok, new_state}
    else
      {:reply, {:error, :not_controller}, state}
    end
  end

  # Internal view_item implementation
  defp do_view_item(state, item_id) do
    case Object3D.get_item(item_id) do
      nil ->
        {:reply, {:error, :item_not_found}, state}

      item ->
        Object3D.mark_item_viewed(item_id)

        # Only use camera presets if the item has them configured
        # Otherwise, keep the current camera position for collaborative viewing
        {camera_position, camera_target} =
          if has_camera_preset?(item) do
            parse_camera_presets(item)
          else
            {state.camera_position, state.camera_target}
          end

        new_state = %{
          state
          | current_item_id: item_id,
            camera_position: camera_position,
            camera_target: camera_target,
            camera_updated_at: DateTime.utc_now()
        }

        broadcast_item_change(new_state, item)
        {:reply, :ok, new_state}
    end
  end

  # Check if item has explicit camera preset configured
  defp has_camera_preset?(item) do
    (item.camera_preset_position != nil and item.camera_preset_position != "") or
      (item.camera_preset_target != nil and item.camera_preset_target != "")
  end

  # Internal next implementation
  defp do_next(state) do
    case Object3D.get_next_item(state.playlist_id, state.current_item_id) do
      nil ->
        {:reply, {:ok, :end_of_playlist}, state}

      item ->
        Object3D.mark_item_viewed(item.id)

        # Preserve camera position unless item has explicit preset
        {camera_position, camera_target} =
          if has_camera_preset?(item) do
            parse_camera_presets(item)
          else
            {state.camera_position, state.camera_target}
          end

        new_state = %{
          state
          | current_item_id: item.id,
            camera_position: camera_position,
            camera_target: camera_target,
            camera_updated_at: DateTime.utc_now()
        }

        broadcast_item_change(new_state, item)
        {:reply, :ok, new_state}
    end
  end

  # Internal previous implementation
  defp do_previous(state) do
    case Object3D.get_previous_item(state.playlist_id, state.current_item_id) do
      nil ->
        {:reply, {:ok, :start_of_playlist}, state}

      item ->
        # Preserve camera position unless item has explicit preset
        {camera_position, camera_target} =
          if has_camera_preset?(item) do
            parse_camera_presets(item)
          else
            {state.camera_position, state.camera_target}
          end

        new_state = %{
          state
          | current_item_id: item.id,
            camera_position: camera_position,
            camera_target: camera_target,
            camera_updated_at: DateTime.utc_now()
        }

        broadcast_item_change(new_state, item)
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_cast({:sync_camera, position, target, user_id}, state) do
    # Only allow camera sync from controller
    if can_control?(state, user_id) do
      new_state = %{
        state
        | camera_position: position,
          camera_target: target,
          camera_updated_at: DateTime.utc_now()
      }

      # Active camera movement from user interaction
      broadcast_camera_sync(new_state, user_id, true)
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:item_added, item}, %{current_item_id: nil} = state) do
    # No current item - auto-select the newly added item
    Logger.info("Auto-selecting newly added 3D object #{item.id} as current item")

    {camera_position, camera_target} = parse_camera_presets(item)

    new_state = %{
      state
      | current_item_id: item.id,
        camera_position: camera_position,
        camera_target: camera_target,
        camera_updated_at: DateTime.utc_now()
    }

    broadcast_item_change(new_state, item)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:item_added, _item}, state) do
    # Already have a current item, just ignore
    {:noreply, state}
  end

  @impl true
  def handle_info(:heartbeat, state) do
    # Reschedule next heartbeat
    schedule_heartbeat()

    # Broadcast camera state if there's a controller (for followers to sync)
    # This is a passive sync, not active movement
    if state.controller_user_id && state.current_item_id do
      broadcast_camera_sync(state, state.controller_user_id, false)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:control_request_timeout, requester_user_id}, state) do
    # Check if this timeout is still valid (same requester pending)
    if state.pending_request_user_id == requester_user_id do
      Logger.info(
        "Control request timeout - transferring control to #{state.pending_request_user_name}"
      )

      # Transfer control to requester
      new_state = %{
        state
        | controller_user_id: state.pending_request_user_id,
          controller_user_name: state.pending_request_user_name,
          pending_request_user_id: nil,
          pending_request_user_name: nil,
          pending_request_timer_ref: nil
      }

      broadcast_controller_change(new_state)
      {:noreply, new_state}
    else
      # Request was already handled, ignore
      {:noreply, state}
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp pubsub_topic(%{is_lobby: true}), do: "object3d:lobby"
  defp pubsub_topic(%{room_id: room_id}), do: "object3d:#{room_id}"

  defp broadcast_item_change(state, item) do
    Phoenix.PubSub.broadcast(
      Sensocto.PubSub,
      pubsub_topic(state),
      {:object3d_item_changed,
       %{
         item: item,
         camera_position: state.camera_position,
         camera_target: state.camera_target,
         timestamp: DateTime.utc_now()
       }}
    )
  end

  defp broadcast_camera_sync(state, user_id, is_active) do
    Phoenix.PubSub.broadcast(
      Sensocto.PubSub,
      pubsub_topic(state),
      {:object3d_camera_synced,
       %{
         camera_position: state.camera_position,
         camera_target: state.camera_target,
         user_id: user_id,
         is_active: is_active,
         timestamp: DateTime.utc_now()
       }}
    )
  end

  defp broadcast_controller_change(state) do
    Phoenix.PubSub.broadcast(
      Sensocto.PubSub,
      pubsub_topic(state),
      {:object3d_controller_changed,
       %{
         controller_user_id: state.controller_user_id,
         controller_user_name: state.controller_user_name,
         pending_request_user_id: state.pending_request_user_id,
         pending_request_user_name: state.pending_request_user_name
       }}
    )
  end

  defp broadcast_control_request(state, requester_id, requester_name) do
    Phoenix.PubSub.broadcast(
      Sensocto.PubSub,
      pubsub_topic(state),
      {:object3d_control_requested,
       %{
         requester_id: requester_id,
         requester_name: requester_name,
         controller_user_id: state.controller_user_id,
         timeout_seconds: div(@control_request_timeout_ms, 1000)
       }}
    )
  end

  defp broadcast_control_request_denied(state, requester_id) do
    Phoenix.PubSub.broadcast(
      Sensocto.PubSub,
      pubsub_topic(state),
      {:object3d_control_request_denied,
       %{
         requester_id: requester_id,
         controller_user_id: state.controller_user_id
       }}
    )
  end

  defp cancel_pending_request(%{pending_request_timer_ref: nil} = state), do: state

  defp cancel_pending_request(%{pending_request_timer_ref: timer_ref} = state) do
    Process.cancel_timer(timer_ref)

    %{
      state
      | pending_request_user_id: nil,
        pending_request_user_name: nil,
        pending_request_timer_ref: nil
    }
  end

  # Check if a user can control
  # Anyone can control if there's no controller assigned
  # Otherwise, only the current controller can control
  defp can_control?(%{controller_user_id: nil}, _user_id), do: true
  defp can_control?(%{controller_user_id: controller_id}, user_id), do: controller_id == user_id

  # Parse camera presets from item fields
  defp parse_camera_presets(item) do
    position = parse_xyz(item.camera_preset_position, %{x: 0, y: 0, z: 5})
    target = parse_xyz(item.camera_preset_target, %{x: 0, y: 0, z: 0})
    {position, target}
  end

  defp parse_xyz(nil, default), do: default
  defp parse_xyz("", default), do: default

  defp parse_xyz(str, default) when is_binary(str) do
    case String.split(str, ",") do
      [x, y, z] ->
        %{
          x: parse_float(x, default.x),
          y: parse_float(y, default.y),
          z: parse_float(z, default.z)
        }

      _ ->
        default
    end
  end

  defp parse_float(str, default) do
    case Float.parse(String.trim(str)) do
      {val, _} -> val
      :error -> default
    end
  end
end
