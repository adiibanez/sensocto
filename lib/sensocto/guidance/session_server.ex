defmodule Sensocto.Guidance.SessionServer do
  @moduledoc """
  GenServer managing a guided session between a guide and a follower.

  The guide's navigation actions (lens changes, sensor focus, annotations)
  are broadcast to the follower. The follower can break away at any time
  and will drift back after a configurable timeout.

  Follows the MediaPlayerServer take_control/release_control pattern:
  guide writes, follower reads.
  """
  use GenServer
  require Logger

  # Idle timeout: end session if guide disconnects for 5 minutes
  @idle_timeout_ms 5 * 60 * 1000

  defstruct [
    :session_id,
    :guide_user_id,
    :guide_user_name,
    :follower_user_id,
    :follower_user_name,
    :room_id,
    # Guide's navigation state (synced to follower)
    current_lens: :sensors,
    focused_sensor_id: nil,
    annotations: [],
    suggested_action: nil,
    # Guide's lobby settings (synced to follower)
    current_layout: :stacked,
    current_quality: :auto,
    current_sort: :activity,
    current_lobby_mode: :media,
    # Follower state
    follower_connected: false,
    following: true,
    follower_last_active_at: nil,
    drift_back_seconds: 15,
    drift_back_timer_ref: nil,
    # Guide presence
    guide_connected: false,
    idle_timeout_ref: nil
  ]

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(session_id))
  end

  def via_tuple(session_id) do
    {:via, Registry, {Sensocto.GuidanceRegistry, session_id}}
  end

  @doc "Get the current session state."
  def get_state(session_id) do
    GenServer.call(via_tuple(session_id), :get_state)
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc "Guide: change the current lens view."
  def set_lens(session_id, user_id, lens) do
    GenServer.call(via_tuple(session_id), {:set_lens, user_id, lens})
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc "Guide: focus on a specific sensor."
  def set_focused_sensor(session_id, user_id, sensor_id) do
    GenServer.call(via_tuple(session_id), {:set_focused_sensor, user_id, sensor_id})
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc "Guide: add an annotation."
  def add_annotation(session_id, user_id, annotation) do
    GenServer.call(via_tuple(session_id), {:add_annotation, user_id, annotation})
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc "Guide: suggest an action to the follower."
  def suggest_action(session_id, user_id, action) do
    GenServer.call(via_tuple(session_id), {:suggest_action, user_id, action})
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc "Guide: change the lobby layout."
  def set_layout(session_id, user_id, layout) do
    GenServer.call(via_tuple(session_id), {:set_layout, user_id, layout})
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc "Guide: change the data quality setting."
  def set_quality(session_id, user_id, quality) do
    GenServer.call(via_tuple(session_id), {:set_quality, user_id, quality})
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc "Guide: change the sensor sort order."
  def set_sort(session_id, user_id, sort_by) do
    GenServer.call(via_tuple(session_id), {:set_sort, user_id, sort_by})
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc "Guide: change the lobby content mode."
  def set_lobby_mode(session_id, user_id, mode) do
    GenServer.call(via_tuple(session_id), {:set_lobby_mode, user_id, mode})
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc "Follower: stop following, start drift-back timer."
  def break_away(session_id, user_id) do
    GenServer.call(via_tuple(session_id), {:break_away, user_id})
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc "Follower: reset drift-back timer (still browsing independently)."
  def report_activity(session_id, user_id) do
    GenServer.cast(via_tuple(session_id), {:report_activity, user_id})
  end

  @doc "Follower: resume following immediately."
  def rejoin(session_id, user_id) do
    GenServer.call(via_tuple(session_id), {:rejoin, user_id})
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc "Either party: end the session."
  def end_session(session_id, user_id) do
    GenServer.call(via_tuple(session_id), {:end_session, user_id})
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc "Mark a user as connected (called on mount)."
  def connect(session_id, user_id) do
    GenServer.cast(via_tuple(session_id), {:connect, user_id})
  end

  @doc "Mark a user as disconnected (called on terminate)."
  def disconnect(session_id, user_id) do
    GenServer.cast(via_tuple(session_id), {:disconnect, user_id})
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    guide_user_id = Keyword.fetch!(opts, :guide_user_id)
    guide_user_name = Keyword.get(opts, :guide_user_name, "Guide")
    follower_user_id = Keyword.get(opts, :follower_user_id)
    follower_user_name = Keyword.get(opts, :follower_user_name, "Follower")
    room_id = Keyword.get(opts, :room_id)
    drift_back_seconds = Keyword.get(opts, :drift_back_seconds, 15)

    Logger.info("Starting SessionServer for session #{session_id}")

    state = %__MODULE__{
      session_id: session_id,
      guide_user_id: guide_user_id,
      guide_user_name: guide_user_name,
      follower_user_id: follower_user_id,
      follower_user_name: follower_user_name,
      room_id: room_id,
      drift_back_seconds: drift_back_seconds
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    response = %{
      session_id: state.session_id,
      guide_user_id: state.guide_user_id,
      guide_user_name: state.guide_user_name,
      follower_user_id: state.follower_user_id,
      follower_user_name: state.follower_user_name,
      room_id: state.room_id,
      current_lens: state.current_lens,
      focused_sensor_id: state.focused_sensor_id,
      annotations: state.annotations,
      suggested_action: state.suggested_action,
      follower_connected: state.follower_connected,
      following: state.following,
      guide_connected: state.guide_connected,
      layout: state.current_layout,
      quality: state.current_quality,
      sort_by: state.current_sort,
      lobby_mode: state.current_lobby_mode
    }

    {:reply, {:ok, response}, state}
  end

  @impl true
  def handle_call({:set_lens, user_id, lens}, _from, state) do
    if is_guide?(state, user_id) do
      new_state = %{state | current_lens: lens}
      broadcast(state, {:guided_lens_changed, %{lens: lens}})
      {:reply, :ok, new_state}
    else
      {:reply, {:error, :not_guide}, state}
    end
  end

  @impl true
  def handle_call({:set_focused_sensor, user_id, sensor_id}, _from, state) do
    if is_guide?(state, user_id) do
      new_state = %{state | focused_sensor_id: sensor_id}
      broadcast(state, {:guided_sensor_focused, %{sensor_id: sensor_id}})
      {:reply, :ok, new_state}
    else
      {:reply, {:error, :not_guide}, state}
    end
  end

  @impl true
  def handle_call({:add_annotation, user_id, annotation}, _from, state) do
    if is_guide?(state, user_id) do
      annotation = Map.put(annotation, :id, Ash.UUID.generate())
      new_state = %{state | annotations: state.annotations ++ [annotation]}
      broadcast(state, {:guided_annotation, %{annotation: annotation}})
      {:reply, :ok, new_state}
    else
      {:reply, {:error, :not_guide}, state}
    end
  end

  @impl true
  def handle_call({:suggest_action, user_id, action}, _from, state) do
    if is_guide?(state, user_id) do
      new_state = %{state | suggested_action: action}
      broadcast(state, {:guided_suggestion, %{action: action}})
      {:reply, :ok, new_state}
    else
      {:reply, {:error, :not_guide}, state}
    end
  end

  @impl true
  def handle_call({:set_layout, user_id, layout}, _from, state) do
    if is_guide?(state, user_id) do
      new_state = %{state | current_layout: layout}
      broadcast(state, {:guided_layout_changed, %{layout: layout}})
      {:reply, :ok, new_state}
    else
      {:reply, {:error, :not_guide}, state}
    end
  end

  @impl true
  def handle_call({:set_quality, user_id, quality}, _from, state) do
    if is_guide?(state, user_id) do
      new_state = %{state | current_quality: quality}
      broadcast(state, {:guided_quality_changed, %{quality: quality}})
      {:reply, :ok, new_state}
    else
      {:reply, {:error, :not_guide}, state}
    end
  end

  @impl true
  def handle_call({:set_sort, user_id, sort_by}, _from, state) do
    if is_guide?(state, user_id) do
      new_state = %{state | current_sort: sort_by}
      broadcast(state, {:guided_sort_changed, %{sort_by: sort_by}})
      {:reply, :ok, new_state}
    else
      {:reply, {:error, :not_guide}, state}
    end
  end

  @impl true
  def handle_call({:set_lobby_mode, user_id, mode}, _from, state) do
    if is_guide?(state, user_id) do
      new_state = %{state | current_lobby_mode: mode}
      broadcast(state, {:guided_mode_changed, %{mode: mode}})
      {:reply, :ok, new_state}
    else
      {:reply, {:error, :not_guide}, state}
    end
  end

  @impl true
  def handle_call({:break_away, user_id}, _from, state) do
    if is_follower?(state, user_id) do
      state = cancel_drift_back_timer(state)

      timer_ref =
        Process.send_after(self(), :drift_back, state.drift_back_seconds * 1000)

      new_state = %{
        state
        | following: false,
          follower_last_active_at: DateTime.utc_now(),
          drift_back_timer_ref: timer_ref
      }

      broadcast(state, {:guided_break_away, %{follower_user_id: user_id}})
      {:reply, :ok, new_state}
    else
      {:reply, {:error, :not_follower}, state}
    end
  end

  @impl true
  def handle_call({:rejoin, user_id}, _from, state) do
    if is_follower?(state, user_id) do
      state = cancel_drift_back_timer(state)

      new_state = %{
        state
        | following: true,
          drift_back_timer_ref: nil
      }

      broadcast(state, {:guided_rejoin, %{follower_user_id: user_id}})

      {:reply,
       {:ok,
        %{
          lens: state.current_lens,
          focused_sensor_id: state.focused_sensor_id,
          layout: state.current_layout,
          quality: state.current_quality,
          sort_by: state.current_sort,
          lobby_mode: state.current_lobby_mode
        }}, new_state}
    else
      {:reply, {:error, :not_follower}, state}
    end
  end

  @impl true
  def handle_call({:end_session, user_id}, _from, state) do
    if is_guide?(state, user_id) or is_follower?(state, user_id) do
      state = cancel_drift_back_timer(state)
      cancel_idle_timeout(state)

      # Update the Ash resource
      case Ash.get(Sensocto.Guidance.GuidedSession, state.session_id, authorize?: false) do
        {:ok, session} ->
          Ash.update(session, %{}, action: :end_session, authorize?: false)

        _ ->
          :ok
      end

      broadcast(state, {:guided_ended, %{ended_by: user_id}})
      {:stop, :normal, :ok, state}
    else
      {:reply, {:error, :not_participant}, state}
    end
  end

  @impl true
  def handle_cast({:connect, user_id}, state) do
    new_state =
      cond do
        is_guide?(state, user_id) ->
          state = cancel_idle_timeout(state)
          %{state | guide_connected: true}

        is_follower?(state, user_id) ->
          %{state | follower_connected: true}

        true ->
          state
      end

    broadcast(new_state, {:guided_presence, presence_payload(new_state)})
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:disconnect, user_id}, state) do
    new_state =
      cond do
        is_guide?(state, user_id) ->
          idle_ref = Process.send_after(self(), :idle_timeout, @idle_timeout_ms)
          %{state | guide_connected: false, idle_timeout_ref: idle_ref}

        is_follower?(state, user_id) ->
          %{state | follower_connected: false}

        true ->
          state
      end

    broadcast(new_state, {:guided_presence, presence_payload(new_state)})
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:report_activity, user_id}, state) do
    if is_follower?(state, user_id) and not state.following do
      # Reset drift-back timer
      state = cancel_drift_back_timer(state)

      timer_ref =
        Process.send_after(self(), :drift_back, state.drift_back_seconds * 1000)

      new_state = %{
        state
        | follower_last_active_at: DateTime.utc_now(),
          drift_back_timer_ref: timer_ref
      }

      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:drift_back, state) do
    if not state.following do
      new_state = %{state | following: true, drift_back_timer_ref: nil}

      broadcast(
        new_state,
        {:guided_drift_back,
         %{
           lens: state.current_lens,
           focused_sensor_id: state.focused_sensor_id,
           layout: state.current_layout,
           quality: state.current_quality,
           sort_by: state.current_sort,
           lobby_mode: state.current_lobby_mode
         }}
      )

      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:idle_timeout, state) do
    Logger.info("Guided session #{state.session_id} ending due to guide idle timeout")

    case Ash.get(Sensocto.Guidance.GuidedSession, state.session_id, authorize?: false) do
      {:ok, session} ->
        Ash.update(session, %{}, action: :end_session, authorize?: false)

      _ ->
        :ok
    end

    broadcast(state, {:guided_ended, %{ended_by: :idle_timeout}})
    {:stop, :normal, state}
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp is_guide?(%{guide_user_id: guide_id}, user_id) do
    to_string(guide_id) == to_string(user_id)
  end

  defp is_follower?(%{follower_user_id: nil}, _user_id), do: false

  defp is_follower?(%{follower_user_id: follower_id}, user_id) do
    to_string(follower_id) == to_string(user_id)
  end

  defp pubsub_topic(%{session_id: session_id}), do: "guidance:#{session_id}"

  defp broadcast(state, message) do
    Phoenix.PubSub.broadcast(Sensocto.PubSub, pubsub_topic(state), message)
  end

  defp presence_payload(state) do
    %{
      guide_connected: state.guide_connected,
      follower_connected: state.follower_connected,
      following: state.following
    }
  end

  defp cancel_drift_back_timer(%{drift_back_timer_ref: nil} = state), do: state

  defp cancel_drift_back_timer(%{drift_back_timer_ref: ref} = state) do
    Process.cancel_timer(ref)
    %{state | drift_back_timer_ref: nil}
  end

  defp cancel_idle_timeout(%{idle_timeout_ref: nil} = state), do: state

  defp cancel_idle_timeout(%{idle_timeout_ref: ref} = state) do
    Process.cancel_timer(ref)
    %{state | idle_timeout_ref: nil}
  end
end
