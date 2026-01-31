defmodule Sensocto.Accounts.GuestUserStore do
  @moduledoc """
  Storage for guest users with database persistence.

  Guest users are temporary, session-only users that persist across server restarts
  but are automatically cleaned up after extended inactivity.

  ## Architecture

  Uses a hybrid approach:
  - In-memory ETS for fast reads (loaded from DB on init)
  - Database writes for persistence
  - Background sync to handle any drift
  """
  use GenServer
  require Logger

  alias Sensocto.Accounts.GuestSession

  # Cleanup runs every hour to check for inactive guests
  @cleanup_interval :timer.hours(1)
  # Guests remain active for 30 days of inactivity before cleanup
  @guest_ttl_days 30
  @ets_table :guest_users

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
  Fast read from ETS cache.
  """
  def get_guest(guest_id) do
    case :ets.lookup(@ets_table, guest_id) do
      [{^guest_id, guest}] -> {:ok, guest}
      [] -> {:error, :not_found}
    end
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
    guests = :ets.tab2list(@ets_table) |> Enum.map(fn {_id, guest} -> guest end)
    {:ok, guests}
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Create ETS table for fast reads
    :ets.new(@ets_table, [:named_table, :public, :set, read_concurrency: true])

    # Load existing guests from database
    load_guests_from_db()

    # Schedule periodic cleanup
    schedule_cleanup()

    Logger.info("[GuestUserStore] Started with database persistence")

    {:ok, %{last_cleanup: System.system_time(:millisecond)}}
  end

  @impl true
  def handle_call({:create_guest, display_name}, _from, state) do
    guest_id = generate_guest_id()
    token = generate_token()
    now = DateTime.utc_now()

    display_name = display_name || "Guest #{String.slice(guest_id, 0..5)}"

    # Persist to database first
    case create_guest_session(guest_id, display_name, token) do
      {:ok, _session} ->
        guest = %{
          id: guest_id,
          display_name: display_name,
          token: token,
          is_guest: true,
          created_at: DateTime.to_unix(now, :millisecond),
          last_active: DateTime.to_unix(now, :millisecond)
        }

        # Cache in ETS
        :ets.insert(@ets_table, {guest_id, guest})

        Logger.info("[GuestUserStore] Created guest user: #{guest_id}")
        {:reply, {:ok, guest}, state}

      {:error, reason} ->
        Logger.error("[GuestUserStore] Failed to create guest: #{inspect(reason)}")
        {:reply, {:error, :creation_failed}, state}
    end
  end

  @impl true
  def handle_cast({:touch_guest, guest_id}, state) do
    case :ets.lookup(@ets_table, guest_id) do
      [{^guest_id, guest}] ->
        now = System.system_time(:millisecond)
        updated_guest = %{guest | last_active: now}
        :ets.insert(@ets_table, {guest_id, updated_guest})

        # Async update to database (non-blocking)
        spawn(fn -> touch_guest_session(guest_id) end)

        {:noreply, state}

      [] ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:remove_guest, guest_id}, state) do
    Logger.info("[GuestUserStore] Removing guest user: #{guest_id}")

    # Remove from ETS
    :ets.delete(@ets_table, guest_id)

    # Remove from database
    spawn(fn -> delete_guest_session(guest_id) end)

    {:noreply, state}
  end

  @impl true
  def handle_info(:cleanup_inactive_guests, state) do
    now = DateTime.utc_now()
    cutoff = DateTime.add(now, -@guest_ttl_days, :day)

    # Cleanup from database
    case cleanup_expired_sessions(cutoff) do
      {:ok, count} when count > 0 ->
        Logger.info("[GuestUserStore] Cleaned up #{count} expired guest session(s)")

      _ ->
        :ok
    end

    # Reload from database to sync ETS
    load_guests_from_db()

    schedule_cleanup()

    {:noreply, %{state | last_cleanup: System.system_time(:millisecond)}}
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

  # Database operations

  defp load_guests_from_db do
    case Ash.read(GuestSession) do
      {:ok, sessions} ->
        # Clear ETS and reload
        :ets.delete_all_objects(@ets_table)

        Enum.each(sessions, fn session ->
          guest = %{
            id: session.id,
            display_name: session.display_name,
            token: session.token,
            is_guest: true,
            created_at: DateTime.to_unix(session.inserted_at, :millisecond),
            last_active: DateTime.to_unix(session.last_active_at, :millisecond)
          }

          :ets.insert(@ets_table, {session.id, guest})
        end)

        Logger.info("[GuestUserStore] Loaded #{length(sessions)} guest(s) from database")

      {:error, reason} ->
        Logger.error("[GuestUserStore] Failed to load guests from DB: #{inspect(reason)}")
    end
  end

  defp create_guest_session(guest_id, display_name, token) do
    GuestSession
    |> Ash.Changeset.for_create(:create, %{
      id: guest_id,
      display_name: display_name,
      token: token
    })
    |> Ash.create()
  end

  defp touch_guest_session(guest_id) do
    case Ash.get(GuestSession, guest_id) do
      {:ok, session} ->
        session
        |> Ash.Changeset.for_update(:touch, %{})
        |> Ash.update()

      _ ->
        :ok
    end
  end

  defp delete_guest_session(guest_id) do
    case Ash.get(GuestSession, guest_id) do
      {:ok, session} ->
        Ash.destroy(session)

      _ ->
        :ok
    end
  end

  defp cleanup_expired_sessions(cutoff) do
    case Ash.read(GuestSession, action: :expired, arguments: %{before: cutoff}) do
      {:ok, expired_sessions} ->
        Enum.each(expired_sessions, fn session ->
          :ets.delete(@ets_table, session.id)
          Ash.destroy(session)
        end)

        {:ok, length(expired_sessions)}

      {:error, reason} ->
        Logger.error("[GuestUserStore] Failed to cleanup expired sessions: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
