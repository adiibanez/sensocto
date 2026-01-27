defmodule Sensocto.Whiteboard.WhiteboardServer do
  @moduledoc """
  GenServer managing synchronized whiteboard state for a room or lobby.
  Coordinates strokes, canvas operations, and control across all connected clients.
  """
  use GenServer
  require Logger

  # Timeout for control request (30 seconds)
  @control_request_timeout_ms 30_000

  # Stroke batching interval for scalability
  # Batches strokes over 50ms before broadcasting to reduce message fan-out
  @stroke_batch_interval_ms 50

  defstruct [
    :room_id,
    :controller_user_id,
    :controller_user_name,
    :pending_request_user_id,
    :pending_request_user_name,
    :pending_request_timer_ref,
    :stroke_batch_timer_ref,
    strokes: [],
    # Pending strokes to batch before broadcasting
    stroke_batch: [],
    background_color: "#1a1a1a",
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
    {:via, Registry, {Sensocto.WhiteboardRegistry, room_id}}
  end

  @doc """
  Gets the current whiteboard state.
  """
  def get_state(room_id) do
    GenServer.call(via_tuple(room_id), :get_state)
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc """
  Adds a stroke to the whiteboard.
  """
  def add_stroke(room_id, stroke, user_id) do
    GenServer.call(via_tuple(room_id), {:add_stroke, stroke, user_id})
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc """
  Clears all strokes from the whiteboard.
  """
  def clear(room_id, user_id) do
    GenServer.call(via_tuple(room_id), {:clear, user_id})
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc """
  Undoes the last stroke.
  """
  def undo(room_id, user_id) do
    GenServer.call(via_tuple(room_id), {:undo, user_id})
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc """
  Sets the background color.
  """
  def set_background(room_id, color, user_id) do
    GenServer.call(via_tuple(room_id), {:set_background, color, user_id})
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc """
  Takes control of the whiteboard.
  """
  def take_control(room_id, user_id, user_name) do
    GenServer.call(via_tuple(room_id), {:take_control, user_id, user_name})
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc """
  Releases control of the whiteboard.
  """
  def release_control(room_id, user_id) do
    GenServer.call(via_tuple(room_id), {:release_control, user_id})
  catch
    :exit, _ -> {:error, :not_found}
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
  Cancels a pending control request (called by the requester).
  """
  def cancel_request(room_id, user_id) do
    GenServer.call(via_tuple(room_id), {:cancel_request, user_id})
  catch
    :exit, _ -> {:error, :not_found}
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    room_id = Keyword.fetch!(opts, :room_id)
    is_lobby = Keyword.get(opts, :is_lobby, false)

    Logger.info(
      "Starting WhiteboardServer for #{if is_lobby, do: "lobby", else: "room #{room_id}"}"
    )

    state = %__MODULE__{
      room_id: room_id,
      is_lobby: is_lobby,
      strokes: [],
      background_color: "#1a1a1a"
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    response = %{
      strokes: state.strokes,
      background_color: state.background_color,
      controller_user_id: state.controller_user_id,
      controller_user_name: state.controller_user_name,
      pending_request_user_id: state.pending_request_user_id,
      pending_request_user_name: state.pending_request_user_name
    }

    {:reply, {:ok, response}, state}
  end

  @impl true
  def handle_call({:add_stroke, stroke, user_id}, _from, state) do
    if can_control?(state, user_id) do
      # Add unique ID and timestamp to stroke
      stroke =
        stroke
        |> Map.put(:id, Ecto.UUID.generate())
        |> Map.put(:user_id, user_id)
        |> Map.put(:timestamp, DateTime.utc_now())

      # Add to permanent strokes and to batch
      new_state = %{
        state
        | strokes: state.strokes ++ [stroke],
          stroke_batch: state.stroke_batch ++ [stroke]
      }

      # Schedule batch flush if not already scheduled
      new_state =
        if is_nil(state.stroke_batch_timer_ref) do
          timer_ref = Process.send_after(self(), :flush_stroke_batch, @stroke_batch_interval_ms)
          %{new_state | stroke_batch_timer_ref: timer_ref}
        else
          new_state
        end

      {:reply, {:ok, stroke}, new_state}
    else
      {:reply, {:error, :not_controller}, state}
    end
  end

  @impl true
  def handle_call({:clear, user_id}, _from, state) do
    if can_control?(state, user_id) do
      new_state = %{state | strokes: []}
      broadcast_cleared(new_state)
      {:reply, :ok, new_state}
    else
      {:reply, {:error, :not_controller}, state}
    end
  end

  @impl true
  def handle_call({:undo, user_id}, _from, state) do
    if can_control?(state, user_id) do
      case state.strokes do
        [] ->
          {:reply, {:ok, nil}, state}

        strokes ->
          {removed, remaining} = List.pop_at(strokes, -1)
          new_state = %{state | strokes: remaining}
          broadcast_undo(new_state, removed)
          {:reply, {:ok, removed}, new_state}
      end
    else
      {:reply, {:error, :not_controller}, state}
    end
  end

  @impl true
  def handle_call({:set_background, color, user_id}, _from, state) do
    if can_control?(state, user_id) do
      new_state = %{state | background_color: color}
      broadcast_background_changed(new_state, color)
      {:reply, :ok, new_state}
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
    if to_string(state.controller_user_id) == to_string(user_id) do
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
      to_string(state.controller_user_id) == to_string(user_id) ->
        {:reply, {:ok, :already_controller}, state}

      # Someone else is controller - start pending request with timer
      true ->
        state = cancel_pending_request(state)

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

        broadcast_control_request(new_state, user_id, user_name)
        {:reply, {:ok, :request_pending}, new_state}
    end
  end

  @impl true
  def handle_call({:keep_control, user_id}, _from, state) do
    if to_string(state.controller_user_id) == to_string(user_id) &&
         state.pending_request_user_id do
      new_state = cancel_pending_request(state)
      broadcast_control_request_denied(new_state, state.pending_request_user_id)
      {:reply, :ok, new_state}
    else
      {:reply, {:error, :not_controller}, state}
    end
  end

  @impl true
  def handle_call({:cancel_request, user_id}, _from, state) do
    if state.pending_request_user_id &&
         to_string(state.pending_request_user_id) == to_string(user_id) do
      new_state = cancel_pending_request(state)
      broadcast_control_request_cancelled(new_state)
      {:reply, :ok, new_state}
    else
      {:reply, {:error, :no_pending_request}, state}
    end
  end

  @impl true
  def handle_info({:control_request_timeout, requester_id}, state) do
    if state.pending_request_user_id &&
         to_string(state.pending_request_user_id) == to_string(requester_id) do
      # Auto-transfer control to requester
      new_state = %{
        state
        | controller_user_id: state.pending_request_user_id,
          controller_user_name: state.pending_request_user_name,
          pending_request_user_id: nil,
          pending_request_user_name: nil,
          pending_request_timer_ref: nil
      }

      Logger.info(
        "Whiteboard control auto-transferred to #{new_state.controller_user_name} after timeout"
      )

      broadcast_controller_change(new_state)
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:flush_stroke_batch, state) do
    # Broadcast batched strokes if any
    if state.stroke_batch != [] do
      broadcast_strokes_batch(state, state.stroke_batch)
    end

    {:noreply, %{state | stroke_batch: [], stroke_batch_timer_ref: nil}}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp can_control?(state, user_id) do
    # Anyone can control if no controller is set
    is_nil(state.controller_user_id) ||
      to_string(state.controller_user_id) == to_string(user_id)
  end

  defp cancel_pending_request(state) do
    if state.pending_request_timer_ref do
      Process.cancel_timer(state.pending_request_timer_ref)
    end

    %{
      state
      | pending_request_user_id: nil,
        pending_request_user_name: nil,
        pending_request_timer_ref: nil
    }
  end

  defp pubsub_topic(state) do
    if state.is_lobby do
      "whiteboard:lobby"
    else
      "whiteboard:#{state.room_id}"
    end
  end

  defp broadcast_cleared(state) do
    Phoenix.PubSub.broadcast(
      Sensocto.PubSub,
      pubsub_topic(state),
      {:whiteboard_cleared, %{}}
    )
  end

  defp broadcast_undo(state, removed_stroke) do
    Phoenix.PubSub.broadcast(
      Sensocto.PubSub,
      pubsub_topic(state),
      {:whiteboard_undo, %{removed_stroke: removed_stroke}}
    )
  end

  defp broadcast_background_changed(state, color) do
    Phoenix.PubSub.broadcast(
      Sensocto.PubSub,
      pubsub_topic(state),
      {:whiteboard_background_changed, %{color: color}}
    )
  end

  defp broadcast_controller_change(state) do
    Phoenix.PubSub.broadcast(
      Sensocto.PubSub,
      pubsub_topic(state),
      {:whiteboard_controller_changed,
       %{
         controller_user_id: state.controller_user_id,
         controller_user_name: state.controller_user_name
       }}
    )
  end

  defp broadcast_control_request(state, requester_id, requester_name) do
    Phoenix.PubSub.broadcast(
      Sensocto.PubSub,
      pubsub_topic(state),
      {:whiteboard_control_requested,
       %{
         requester_id: requester_id,
         requester_name: requester_name
       }}
    )
  end

  defp broadcast_control_request_denied(state, requester_id) do
    Phoenix.PubSub.broadcast(
      Sensocto.PubSub,
      pubsub_topic(state),
      {:whiteboard_control_request_denied, %{requester_id: requester_id}}
    )
  end

  defp broadcast_control_request_cancelled(state) do
    Phoenix.PubSub.broadcast(
      Sensocto.PubSub,
      pubsub_topic(state),
      {:whiteboard_control_request_cancelled, %{}}
    )
  end

  defp broadcast_strokes_batch(state, strokes) do
    Phoenix.PubSub.broadcast(
      Sensocto.PubSub,
      pubsub_topic(state),
      {:whiteboard_strokes_batch, %{strokes: strokes}}
    )
  end
end
