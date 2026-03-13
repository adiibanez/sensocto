defmodule Sensocto.Avatar.AvatarEcosystemServer do
  @moduledoc """
  Manages control state for the lobby avatar ecosystem.
  Follows the same take/request/release control pattern as
  MediaPlayerServer, Object3DPlayerServer, and WhiteboardServer.
  """
  use GenServer
  require Logger

  @control_request_timeout_ms 30_000

  defstruct [
    :controller_user_id,
    :controller_user_name,
    :pending_request_user_id,
    :pending_request_user_name,
    :pending_request_timer_ref
  ]

  # --- Client API ---

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %__MODULE__{}, name: __MODULE__)
  end

  def take_control(user_id, user_name) do
    GenServer.call(__MODULE__, {:take_control, user_id, user_name})
  catch
    :exit, _ -> {:error, :not_found}
  end

  def release_control(user_id) do
    GenServer.call(__MODULE__, {:release_control, user_id})
  catch
    :exit, _ -> {:error, :not_found}
  end

  def request_control(user_id, user_name) do
    GenServer.call(__MODULE__, {:request_control, user_id, user_name})
  catch
    :exit, _ -> {:error, :not_found}
  end

  def keep_control(user_id) do
    GenServer.call(__MODULE__, {:keep_control, user_id})
  catch
    :exit, _ -> {:error, :not_found}
  end

  def cancel_request(user_id) do
    GenServer.call(__MODULE__, {:cancel_request, user_id})
  catch
    :exit, _ -> {:error, :not_found}
  end

  def get_state do
    GenServer.call(__MODULE__, :get_state)
  catch
    :exit, _ ->
      %{
        controller_user_id: nil,
        controller_user_name: nil,
        pending_request_user_id: nil,
        pending_request_user_name: nil
      }
  end

  # --- Server Callbacks ---

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:take_control, user_id, user_name}, _from, state) do
    state = cancel_pending_request(state)

    new_state = %{state | controller_user_id: user_id, controller_user_name: user_name}

    broadcast(:avatar_controller_changed, %{
      controller_user_id: user_id,
      controller_user_name: user_name
    })

    {:reply, :ok, new_state}
  end

  def handle_call({:release_control, user_id}, _from, state) do
    if to_string(state.controller_user_id) == to_string(user_id) do
      state = cancel_pending_request(state)

      new_state = %{state | controller_user_id: nil, controller_user_name: nil}

      broadcast(:avatar_controller_changed, %{
        controller_user_id: nil,
        controller_user_name: nil
      })

      {:reply, :ok, new_state}
    else
      {:reply, {:error, :not_controller}, state}
    end
  end

  def handle_call({:request_control, user_id, user_name}, _from, state) do
    cond do
      is_nil(state.controller_user_id) ->
        new_state = %{state | controller_user_id: user_id, controller_user_name: user_name}

        broadcast(:avatar_controller_changed, %{
          controller_user_id: user_id,
          controller_user_name: user_name
        })

        {:reply, {:ok, :control_granted}, new_state}

      to_string(state.controller_user_id) == to_string(user_id) ->
        {:reply, {:ok, :already_controller}, state}

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

        broadcast(:avatar_control_requested, %{
          requester_id: user_id,
          requester_name: user_name
        })

        {:reply, {:ok, :request_pending}, new_state}
    end
  end

  def handle_call({:keep_control, user_id}, _from, state) do
    if to_string(state.controller_user_id) == to_string(user_id) &&
         state.pending_request_user_id do
      requester_id = state.pending_request_user_id
      new_state = cancel_pending_request(state)
      broadcast(:avatar_control_request_denied, %{requester_id: requester_id})
      {:reply, :ok, new_state}
    else
      {:reply, {:error, :not_controller}, state}
    end
  end

  def handle_call({:cancel_request, user_id}, _from, state) do
    if state.pending_request_user_id &&
         to_string(state.pending_request_user_id) == to_string(user_id) do
      new_state = cancel_pending_request(state)
      {:reply, :ok, new_state}
    else
      {:reply, {:error, :not_requester}, state}
    end
  end

  def handle_call(:get_state, _from, state) do
    {:reply,
     %{
       controller_user_id: state.controller_user_id,
       controller_user_name: state.controller_user_name,
       pending_request_user_id: state.pending_request_user_id,
       pending_request_user_name: state.pending_request_user_name
     }, state}
  end

  @impl true
  def handle_info({:control_request_timeout, requester_id}, state) do
    if state.pending_request_user_id &&
         to_string(state.pending_request_user_id) == to_string(requester_id) do
      new_state = %{
        state
        | controller_user_id: state.pending_request_user_id,
          controller_user_name: state.pending_request_user_name,
          pending_request_user_id: nil,
          pending_request_user_name: nil,
          pending_request_timer_ref: nil
      }

      Logger.info(
        "Avatar control auto-transferred to #{new_state.controller_user_name} after timeout"
      )

      broadcast(:avatar_controller_changed, %{
        controller_user_id: new_state.controller_user_id,
        controller_user_name: new_state.controller_user_name
      })

      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  # --- Private ---

  defp cancel_pending_request(state) do
    if state.pending_request_timer_ref do
      Process.cancel_timer(state.pending_request_timer_ref)
    end

    if state.pending_request_user_id do
      broadcast(:avatar_control_request_cancelled, %{})
    end

    %{
      state
      | pending_request_user_id: nil,
        pending_request_user_name: nil,
        pending_request_timer_ref: nil
    }
  end

  defp broadcast(event, payload) do
    Phoenix.PubSub.broadcast(Sensocto.PubSub, "avatar:lobby", {event, payload})
  end
end
