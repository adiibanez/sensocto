defmodule Sensocto.Accounts.GuestUserStore do
  @moduledoc """
  In-memory storage for guest users.
  Guest users are temporary, session-only users that don't persist to the database.
  They are automatically cleaned up after inactivity.
  """
  use GenServer
  require Logger

  @cleanup_interval :timer.minutes(5)
  @guest_ttl :timer.hours(2)

  defstruct guests: %{}, last_cleanup: nil

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Create a new guest user with an optional display name.
  Returns a guest user map with a unique ID and token.
  """
  def create_guest(display_name \\ nil) do
    GenServer.call(__MODULE__, {:create_guest, display_name})
  end

  @doc """
  Get a guest user by their ID.
  """
  def get_guest(guest_id) do
    GenServer.call(__MODULE__, {:get_guest, guest_id})
  end

  @doc """
  Update the last_active timestamp for a guest user.
  """
  def touch_guest(guest_id) do
    GenServer.cast(__MODULE__, {:touch_guest, guest_id})
  end

  @doc """
  Remove a guest user from the store.
  """
  def remove_guest(guest_id) do
    GenServer.cast(__MODULE__, {:remove_guest, guest_id})
  end

  @doc """
  Get all currently active guest users.
  """
  def list_guests do
    GenServer.call(__MODULE__, :list_guests)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    schedule_cleanup()

    {:ok,
     %__MODULE__{
       guests: %{},
       last_cleanup: System.system_time(:millisecond)
     }}
  end

  @impl true
  def handle_call({:create_guest, display_name}, _from, state) do
    guest_id = generate_guest_id()
    token = generate_token()

    now = System.system_time(:millisecond)

    guest = %{
      id: guest_id,
      display_name: display_name || "Guest #{String.slice(guest_id, 0..5)}",
      token: token,
      is_guest: true,
      created_at: now,
      last_active: now
    }

    new_state = %{state | guests: Map.put(state.guests, guest_id, guest)}

    Logger.info("Created guest user: #{guest_id}")

    {:reply, {:ok, guest}, new_state}
  end

  @impl true
  def handle_call({:get_guest, guest_id}, _from, state) do
    case Map.get(state.guests, guest_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      guest ->
        {:reply, {:ok, guest}, state}
    end
  end

  @impl true
  def handle_call(:list_guests, _from, state) do
    guests = Map.values(state.guests)
    {:reply, {:ok, guests}, state}
  end

  @impl true
  def handle_cast({:touch_guest, guest_id}, state) do
    case Map.get(state.guests, guest_id) do
      nil ->
        {:noreply, state}

      guest ->
        updated_guest = %{guest | last_active: System.system_time(:millisecond)}
        new_guests = Map.put(state.guests, guest_id, updated_guest)
        {:noreply, %{state | guests: new_guests}}
    end
  end

  @impl true
  def handle_cast({:remove_guest, guest_id}, state) do
    Logger.info("Removing guest user: #{guest_id}")
    new_guests = Map.delete(state.guests, guest_id)
    {:noreply, %{state | guests: new_guests}}
  end

  @impl true
  def handle_info(:cleanup_inactive_guests, state) do
    now = System.system_time(:millisecond)
    cutoff = now - @guest_ttl

    {active_guests, inactive_count} =
      Enum.reduce(state.guests, {%{}, 0}, fn {id, guest}, {acc, count} ->
        if guest.last_active >= cutoff do
          {Map.put(acc, id, guest), count}
        else
          Logger.info("Cleaning up inactive guest: #{id}")
          {acc, count + 1}
        end
      end)

    if inactive_count > 0 do
      Logger.info("Cleaned up #{inactive_count} inactive guest user(s)")
    end

    schedule_cleanup()

    {:noreply, %{state | guests: active_guests, last_cleanup: now}}
  end

  # Private Functions

  defp generate_guest_id do
    "guest_#{:crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)}"
  end

  defp generate_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_inactive_guests, @cleanup_interval)
  end
end
