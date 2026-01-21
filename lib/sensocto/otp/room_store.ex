defmodule Sensocto.RoomStore do
  @moduledoc """
  Main in-memory store for all rooms.

  This GenServer is the single source of truth for room state.
  All room operations go through this module, which:
  1. Maintains fast in-memory state
  2. Syncs changes to PostgreSQL for persistence (primary)
  3. Async syncs changes to iroh docs for P2P sync (secondary)

  On startup, rooms are hydrated from PostgreSQL to restore state.

  Room data structure:
  ```
  %{
    id: "uuid",
    name: "Room Name",
    description: "Optional description",
    owner_id: "user_uuid",
    join_code: "ABC12345",
    is_public: true,
    configuration: %{},
    members: %{user_id => role},
    sensor_ids: MapSet.t(),
    created_at: DateTime.t(),
    updated_at: DateTime.t()
  }
  ```
  """
  use GenServer
  require Logger

  alias Sensocto.Iroh.RoomStore, as: IrohStore
  alias Sensocto.Sensors.Room, as: RoomResource
  alias Sensocto.Sensors.RoomMembership

  # Default timeout for GenServer calls (5 seconds)
  @call_timeout 5_000

  defstruct [
    # room_id => room_data
    rooms: %{},
    # join_code => room_id
    join_codes: %{},
    # user_id => [room_ids]
    user_rooms: %{},
    # Track if iroh sync is available
    iroh_available: false
  ]

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Creates a new room.
  Returns {:ok, room} or {:error, reason}.
  """
  def create_room(attrs, owner_id) do
    GenServer.call(__MODULE__, {:create_room, attrs, owner_id}, @call_timeout)
  end

  @doc """
  Gets a room by ID.
  Returns {:ok, room} or {:error, :not_found}.
  """
  def get_room(room_id) do
    GenServer.call(__MODULE__, {:get_room, room_id}, @call_timeout)
  end

  @doc """
  Gets a room by join code.
  Returns {:ok, room} or {:error, :not_found}.
  """
  def get_room_by_code(join_code) do
    GenServer.call(__MODULE__, {:get_room_by_code, join_code}, @call_timeout)
  end

  @doc """
  Updates a room's attributes.
  Only owner/admin can update.
  """
  def update_room(room_id, attrs) do
    GenServer.call(__MODULE__, {:update_room, room_id, attrs}, @call_timeout)
  end

  @doc """
  Deletes a room.
  """
  def delete_room(room_id) do
    GenServer.call(__MODULE__, {:delete_room, room_id}, @call_timeout)
  end

  @doc """
  Lists all rooms for a user (owned + member of).
  """
  def list_user_rooms(user_id) do
    GenServer.call(__MODULE__, {:list_user_rooms, user_id}, @call_timeout)
  end

  @doc """
  Lists all public rooms.
  """
  def list_public_rooms do
    GenServer.call(__MODULE__, :list_public_rooms, @call_timeout)
  end

  @doc """
  Lists all rooms (for admin/simulator purposes).
  """
  def list_all_rooms do
    GenServer.call(__MODULE__, :list_all_rooms, @call_timeout)
  end

  @doc """
  Adds a user to a room with a role.
  """
  def join_room(room_id, user_id, role \\ :member) do
    GenServer.call(__MODULE__, {:join_room, room_id, user_id, role}, @call_timeout)
  end

  @doc """
  Removes a user from a room.
  """
  def leave_room(room_id, user_id) do
    GenServer.call(__MODULE__, {:leave_room, room_id, user_id}, @call_timeout)
  end

  @doc """
  Gets the role of a user in a room.
  Returns role atom or nil if not a member.
  """
  def get_member_role(room_id, user_id) do
    GenServer.call(__MODULE__, {:get_member_role, room_id, user_id}, @call_timeout)
  end

  @doc """
  Checks if a user is a member of a room.
  """
  def is_member?(room_id, user_id) do
    GenServer.call(__MODULE__, {:is_member?, room_id, user_id}, @call_timeout)
  end

  @doc """
  Adds a sensor to a room.
  """
  def add_sensor(room_id, sensor_id) do
    GenServer.call(__MODULE__, {:add_sensor, room_id, sensor_id}, @call_timeout)
  end

  @doc """
  Removes a sensor from a room.
  """
  def remove_sensor(room_id, sensor_id) do
    GenServer.call(__MODULE__, {:remove_sensor, room_id, sensor_id}, @call_timeout)
  end

  @doc """
  Regenerates the join code for a room.
  """
  def regenerate_join_code(room_id) do
    GenServer.call(__MODULE__, {:regenerate_join_code, room_id}, @call_timeout)
  end

  @doc """
  Promotes a member to admin.
  Only owners can promote members to admin.
  """
  def promote_to_admin(room_id, user_id) do
    GenServer.call(__MODULE__, {:promote_to_admin, room_id, user_id}, @call_timeout)
  end

  @doc """
  Demotes an admin to member.
  Only owners can demote admins.
  """
  def demote_to_member(room_id, user_id) do
    GenServer.call(__MODULE__, {:demote_to_member, room_id, user_id}, @call_timeout)
  end

  @doc """
  Kicks a user from a room.
  Only owners and admins can kick members.
  Admins cannot kick other admins or the owner.
  """
  def kick_member(room_id, user_id) do
    GenServer.call(__MODULE__, {:kick_member, room_id, user_id}, @call_timeout)
  end

  @doc """
  Lists all members of a room with their roles.
  Returns list of {user_id, role} tuples.
  """
  def list_members(room_id) do
    GenServer.call(__MODULE__, {:list_members, room_id}, @call_timeout)
  end

  @doc """
  Checks if a room exists.
  """
  def exists?(room_id) do
    GenServer.call(__MODULE__, {:exists?, room_id}, @call_timeout)
  end

  @doc """
  Gets room count.
  """
  def count do
    GenServer.call(__MODULE__, :count, @call_timeout)
  end

  @doc """
  Hydrates a room from iroh docs during startup.
  Used by RoomSync to restore persisted state.
  """
  def hydrate_room(room_data) do
    GenServer.call(__MODULE__, {:hydrate_room, room_data}, @call_timeout)
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    # Subscribe to cluster-wide room updates for multi-node sync
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "rooms:cluster")

    # Hydrate from PostgreSQL immediately (primary persistence)
    Process.send_after(self(), :hydrate_from_postgres, 100)

    # Check if iroh store is available after a delay (secondary/P2P)
    Process.send_after(self(), :check_iroh, 1000)

    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_info(:check_iroh, state) do
    iroh_available =
      try do
        IrohStore.ready?()
      catch
        :exit, _ -> false
      end

    if iroh_available do
      Logger.info("[RoomStore] Iroh store is available")
    else
      Logger.debug("[RoomStore] Iroh store not yet available, will retry")
      Process.send_after(self(), :check_iroh, 5000)
    end

    {:noreply, %{state | iroh_available: iroh_available}}
  end

  @impl true
  def handle_info(:hydrate_from_postgres, state) do
    Logger.info("[RoomStore] Hydrating state from PostgreSQL...")

    new_state =
      try do
        # Load all rooms from PostgreSQL with their memberships
        rooms = RoomResource |> Ash.read!(action: :all) |> Ash.load!(:room_memberships)

        Enum.reduce(rooms, state, fn room, acc ->
          # Convert Ash resource to our internal map format
          room_data = %{
            id: room.id,
            name: room.name,
            description: room.description,
            owner_id: room.owner_id,
            join_code: room.join_code,
            is_public: room.is_public,
            configuration: room.configuration || %{},
            members: build_members_map(room),
            sensor_ids: MapSet.new(),
            created_at: room.inserted_at,
            updated_at: room.updated_at
          }

          acc
          |> put_in([Access.key(:rooms), room.id], room_data)
          |> put_in([Access.key(:join_codes), room.join_code], room.id)
          |> hydrate_user_rooms(room_data.members, room.id)
        end)
      rescue
        e ->
          Logger.error("[RoomStore] Failed to hydrate from PostgreSQL: #{inspect(e)}")
          state
      end

    room_count = map_size(new_state.rooms)
    Logger.info("[RoomStore] Hydrated #{room_count} rooms from PostgreSQL")

    {:noreply, new_state}
  end

  # ---- Cluster Sync Messages ----

  @impl true
  def handle_info({:room_created, room_id, origin_node}, state) when origin_node != node() do
    Logger.debug("[RoomStore] Received room_created from #{origin_node} for #{room_id}")
    # Room will be synced via Horde, just log for now
    {:noreply, state}
  end

  @impl true
  def handle_info({:room_deleted, room_id, origin_node}, state) when origin_node != node() do
    Logger.debug("[RoomStore] Received room_deleted from #{origin_node} for #{room_id}")
    # Remove from local state if present (Horde handles process, this handles metadata)
    new_state =
      case Map.get(state.rooms, room_id) do
        nil ->
          state

        room ->
          state
          |> update_in([Access.key(:rooms)], &Map.delete(&1, room_id))
          |> update_in([Access.key(:join_codes)], &Map.delete(&1, room.join_code))
          |> remove_room_from_all_users(room_id, room.members)
      end

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:room_state_sync, room_data, origin_node}, state) when origin_node != node() do
    # Handle full room state sync from another node
    room_id = Map.get(room_data, :id)
    Logger.debug("[RoomStore] Received room_state_sync from #{origin_node} for #{room_id}")

    # Merge into local state
    sensor_ids =
      case Map.get(room_data, :sensor_ids) do
        list when is_list(list) -> MapSet.new(list)
        nil -> MapSet.new()
        mapset -> mapset
      end

    room = Map.put(room_data, :sensor_ids, sensor_ids)

    new_state =
      state
      |> put_in([Access.key(:rooms), room_id], room)
      |> put_in([Access.key(:join_codes), room.join_code], room_id)
      |> hydrate_user_rooms(room.members, room_id)

    {:noreply, new_state}
  end

  # Ignore messages from self
  @impl true
  def handle_info({:room_created, _room_id, origin_node}, state) when origin_node == node() do
    {:noreply, state}
  end

  @impl true
  def handle_info({:room_deleted, _room_id, origin_node}, state) when origin_node == node() do
    {:noreply, state}
  end

  @impl true
  def handle_info({:room_state_sync, _room_data, origin_node}, state)
      when origin_node == node() do
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("[RoomStore] Unknown message: #{inspect(msg)}")
    {:noreply, state}
  end

  # ---- Create Room ----

  @impl true
  def handle_call({:create_room, attrs, owner_id}, _from, state) do
    room_id = Map.get(attrs, :id) || Ecto.UUID.generate()
    join_code = Map.get(attrs, :join_code) || generate_join_code()

    # Check for join code collision
    if Map.has_key?(state.join_codes, join_code) do
      {:reply, {:error, :join_code_taken}, state}
    else
      now = DateTime.utc_now()

      room = %{
        id: room_id,
        name: Map.get(attrs, :name, "Untitled Room"),
        description: Map.get(attrs, :description),
        owner_id: owner_id,
        join_code: join_code,
        is_public: Map.get(attrs, :is_public, true),
        calls_enabled: Map.get(attrs, :calls_enabled, true),
        media_playback_enabled: Map.get(attrs, :media_playback_enabled, true),
        object_3d_enabled: Map.get(attrs, :object_3d_enabled, false),
        configuration: Map.get(attrs, :configuration, %{}),
        members: %{owner_id => :owner},
        sensor_ids: MapSet.new(),
        created_at: now,
        updated_at: now
      }

      new_state =
        state
        |> put_in([Access.key(:rooms), room_id], room)
        |> put_in([Access.key(:join_codes), join_code], room_id)
        |> update_user_rooms(owner_id, room_id, :add)

      # Sync to PostgreSQL (primary persistence) - room first, then owner membership
      sync_room_and_owner_to_postgres(room, owner_id)

      # Async sync to iroh (secondary/P2P)
      async_sync_room(room, state.iroh_available)

      broadcast_room_update(room_id, :room_created)
      # Broadcast to cluster for multi-node sync
      broadcast_cluster_room_created(room_id)
      broadcast_cluster_room_sync(room)

      {:reply, {:ok, room}, new_state}
    end
  end

  # ---- Get Room ----

  @impl true
  def handle_call({:get_room, room_id}, _from, state) do
    case Map.get(state.rooms, room_id) do
      nil -> {:reply, {:error, :not_found}, state}
      room -> {:reply, {:ok, room}, state}
    end
  end

  # ---- Get Room by Code ----

  @impl true
  def handle_call({:get_room_by_code, join_code}, _from, state) do
    case Map.get(state.join_codes, join_code) do
      nil ->
        {:reply, {:error, :not_found}, state}

      room_id ->
        case Map.get(state.rooms, room_id) do
          nil -> {:reply, {:error, :not_found}, state}
          room -> {:reply, {:ok, room}, state}
        end
    end
  end

  # ---- Update Room ----

  @impl true
  def handle_call({:update_room, room_id, attrs}, _from, state) do
    case Map.get(state.rooms, room_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      room ->
        updated_room =
          room
          |> maybe_update(:name, attrs)
          |> maybe_update(:description, attrs)
          |> maybe_update(:is_public, attrs)
          |> maybe_update(:calls_enabled, attrs)
          |> maybe_update(:media_playback_enabled, attrs)
          |> maybe_update(:object_3d_enabled, attrs)
          |> maybe_update(:configuration, attrs)
          |> Map.put(:updated_at, DateTime.utc_now())

        new_state = put_in(state, [Access.key(:rooms), room_id], updated_room)

        # Sync to PostgreSQL (primary persistence)
        sync_room_update_to_postgres(updated_room)

        # Async sync to iroh (secondary/P2P)
        async_sync_room(updated_room, state.iroh_available)

        broadcast_room_update(room_id, :room_updated)

        {:reply, {:ok, updated_room}, new_state}
    end
  end

  # ---- Delete Room ----

  @impl true
  def handle_call({:delete_room, room_id}, _from, state) do
    case Map.get(state.rooms, room_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      room ->
        # Remove from all indices
        new_state =
          state
          |> update_in([Access.key(:rooms)], &Map.delete(&1, room_id))
          |> update_in([Access.key(:join_codes)], &Map.delete(&1, room.join_code))
          |> remove_room_from_all_users(room_id, room.members)

        # Delete from PostgreSQL (primary persistence)
        delete_room_from_postgres(room_id)

        # Async delete from iroh (secondary/P2P)
        async_delete_room(room_id, state.iroh_available)

        broadcast_room_update(room_id, :room_deleted)
        # Broadcast to cluster for multi-node sync
        broadcast_cluster_room_deleted(room_id)

        {:reply, :ok, new_state}
    end
  end

  # ---- List User Rooms ----

  @impl true
  def handle_call({:list_user_rooms, user_id}, _from, state) do
    room_ids = Map.get(state.user_rooms, user_id, [])

    rooms =
      room_ids
      |> Enum.map(&Map.get(state.rooms, &1))
      |> Enum.reject(&is_nil/1)

    {:reply, rooms, state}
  end

  # ---- List Public Rooms ----

  @impl true
  def handle_call(:list_public_rooms, _from, state) do
    rooms =
      state.rooms
      |> Map.values()
      |> Enum.filter(& &1.is_public)

    {:reply, rooms, state}
  end

  @impl true
  def handle_call(:list_all_rooms, _from, state) do
    rooms = Map.values(state.rooms)
    {:reply, rooms, state}
  end

  # ---- Join Room ----

  @impl true
  def handle_call({:join_room, room_id, user_id, role}, _from, state) do
    case Map.get(state.rooms, room_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      room ->
        if Map.has_key?(room.members, user_id) do
          {:reply, {:error, :already_member}, state}
        else
          updated_room =
            room
            |> put_in([Access.key(:members), user_id], role)
            |> Map.put(:updated_at, DateTime.utc_now())

          new_state =
            state
            |> put_in([Access.key(:rooms), room_id], updated_room)
            |> update_user_rooms(user_id, room_id, :add)

          # Sync to PostgreSQL (primary persistence)
          sync_membership_to_postgres(room_id, user_id, role)

          # Async sync to iroh (secondary/P2P)
          async_sync_membership(room_id, user_id, role, state.iroh_available)

          broadcast_room_update(room_id, {:member_joined, user_id, role})

          {:reply, {:ok, updated_room}, new_state}
        end
    end
  end

  # ---- Leave Room ----

  @impl true
  def handle_call({:leave_room, room_id, user_id}, _from, state) do
    case Map.get(state.rooms, room_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      room ->
        if room.owner_id == user_id do
          {:reply, {:error, :owner_cannot_leave}, state}
        else
          updated_room =
            room
            |> update_in([Access.key(:members)], &Map.delete(&1, user_id))
            |> Map.put(:updated_at, DateTime.utc_now())

          new_state =
            state
            |> put_in([Access.key(:rooms), room_id], updated_room)
            |> update_user_rooms(user_id, room_id, :remove)

          # Delete from PostgreSQL (primary persistence)
          delete_membership_from_postgres(room_id, user_id)

          # Async sync to iroh (secondary/P2P)
          async_delete_membership(room_id, user_id, state.iroh_available)

          broadcast_room_update(room_id, {:member_left, user_id})

          {:reply, :ok, new_state}
        end
    end
  end

  # ---- Get Member Role ----

  @impl true
  def handle_call({:get_member_role, room_id, user_id}, _from, state) do
    role =
      case Map.get(state.rooms, room_id) do
        nil -> nil
        room -> Map.get(room.members, user_id)
      end

    {:reply, role, state}
  end

  # ---- Is Member? ----

  @impl true
  def handle_call({:is_member?, room_id, user_id}, _from, state) do
    is_member =
      case Map.get(state.rooms, room_id) do
        nil -> false
        room -> Map.has_key?(room.members, user_id)
      end

    {:reply, is_member, state}
  end

  # ---- Add Sensor ----

  @impl true
  def handle_call({:add_sensor, room_id, sensor_id}, _from, state) do
    case Map.get(state.rooms, room_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      room ->
        updated_room =
          room
          |> update_in([Access.key(:sensor_ids)], &MapSet.put(&1, sensor_id))
          |> Map.put(:updated_at, DateTime.utc_now())

        new_state = put_in(state, [Access.key(:rooms), room_id], updated_room)

        async_sync_room(updated_room, state.iroh_available)

        broadcast_room_update(room_id, {:sensor_added, sensor_id})

        {:reply, :ok, new_state}
    end
  end

  # ---- Remove Sensor ----

  @impl true
  def handle_call({:remove_sensor, room_id, sensor_id}, _from, state) do
    case Map.get(state.rooms, room_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      room ->
        updated_room =
          room
          |> update_in([Access.key(:sensor_ids)], &MapSet.delete(&1, sensor_id))
          |> Map.put(:updated_at, DateTime.utc_now())

        new_state = put_in(state, [Access.key(:rooms), room_id], updated_room)

        async_sync_room(updated_room, state.iroh_available)

        broadcast_room_update(room_id, {:sensor_removed, sensor_id})

        {:reply, :ok, new_state}
    end
  end

  # ---- Promote to Admin ----

  @impl true
  def handle_call({:promote_to_admin, room_id, user_id}, _from, state) do
    case Map.get(state.rooms, room_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      room ->
        case Map.get(room.members, user_id) do
          nil ->
            {:reply, {:error, :not_a_member}, state}

          :owner ->
            {:reply, {:error, :cannot_change_owner}, state}

          :admin ->
            {:reply, {:error, :already_admin}, state}

          :member ->
            updated_room =
              room
              |> put_in([Access.key(:members), user_id], :admin)
              |> Map.put(:updated_at, DateTime.utc_now())

            new_state = put_in(state, [Access.key(:rooms), room_id], updated_room)

            # Sync to PostgreSQL
            update_membership_role_in_postgres(room_id, user_id, :admin)

            broadcast_room_update(room_id, {:member_promoted, user_id, :admin})

            {:reply, {:ok, updated_room}, new_state}
        end
    end
  end

  # ---- Demote to Member ----

  @impl true
  def handle_call({:demote_to_member, room_id, user_id}, _from, state) do
    case Map.get(state.rooms, room_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      room ->
        case Map.get(room.members, user_id) do
          nil ->
            {:reply, {:error, :not_a_member}, state}

          :owner ->
            {:reply, {:error, :cannot_change_owner}, state}

          :member ->
            {:reply, {:error, :already_member}, state}

          :admin ->
            updated_room =
              room
              |> put_in([Access.key(:members), user_id], :member)
              |> Map.put(:updated_at, DateTime.utc_now())

            new_state = put_in(state, [Access.key(:rooms), room_id], updated_room)

            # Sync to PostgreSQL
            update_membership_role_in_postgres(room_id, user_id, :member)

            broadcast_room_update(room_id, {:member_demoted, user_id, :member})

            {:reply, {:ok, updated_room}, new_state}
        end
    end
  end

  # ---- Kick Member ----

  @impl true
  def handle_call({:kick_member, room_id, user_id}, _from, state) do
    case Map.get(state.rooms, room_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      room ->
        case Map.get(room.members, user_id) do
          nil ->
            {:reply, {:error, :not_a_member}, state}

          :owner ->
            {:reply, {:error, :cannot_kick_owner}, state}

          _role ->
            updated_room =
              room
              |> update_in([Access.key(:members)], &Map.delete(&1, user_id))
              |> Map.put(:updated_at, DateTime.utc_now())

            new_state =
              state
              |> put_in([Access.key(:rooms), room_id], updated_room)
              |> update_user_rooms(user_id, room_id, :remove)

            # Delete from PostgreSQL
            delete_membership_from_postgres(room_id, user_id)

            broadcast_room_update(room_id, {:member_kicked, user_id})

            {:reply, {:ok, updated_room}, new_state}
        end
    end
  end

  # ---- List Members ----

  @impl true
  def handle_call({:list_members, room_id}, _from, state) do
    case Map.get(state.rooms, room_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      room ->
        members = Enum.map(room.members, fn {user_id, role} -> {user_id, role} end)
        {:reply, {:ok, members}, state}
    end
  end

  # ---- Regenerate Join Code ----

  @impl true
  def handle_call({:regenerate_join_code, room_id}, _from, state) do
    case Map.get(state.rooms, room_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      room ->
        old_code = room.join_code
        new_code = generate_join_code()

        updated_room =
          room
          |> Map.put(:join_code, new_code)
          |> Map.put(:updated_at, DateTime.utc_now())

        new_state =
          state
          |> put_in([Access.key(:rooms), room_id], updated_room)
          |> update_in([Access.key(:join_codes)], &Map.delete(&1, old_code))
          |> put_in([Access.key(:join_codes), new_code], room_id)

        # Sync to PostgreSQL (primary persistence)
        sync_room_update_to_postgres(updated_room)

        # Async sync to iroh (secondary/P2P)
        async_sync_room(updated_room, state.iroh_available)

        {:reply, {:ok, new_code}, new_state}
    end
  end

  # ---- Exists? ----

  @impl true
  def handle_call({:exists?, room_id}, _from, state) do
    {:reply, Map.has_key?(state.rooms, room_id), state}
  end

  # ---- Count ----

  @impl true
  def handle_call(:count, _from, state) do
    {:reply, map_size(state.rooms), state}
  end

  # ---- Hydrate Room (from iroh docs) ----

  @impl true
  def handle_call({:hydrate_room, room_data}, _from, state) do
    room_id = Map.get(room_data, :id) || Map.get(room_data, "id")

    if room_id == nil do
      {:reply, {:error, :missing_room_id}, state}
    else
      # Convert sensor_ids back to MapSet if it's a list
      sensor_ids =
        case Map.get(room_data, :sensor_ids) || Map.get(room_data, "sensor_ids") do
          list when is_list(list) -> MapSet.new(list)
          nil -> MapSet.new()
          mapset -> mapset
        end

      # Normalize the room data
      room = %{
        id: room_id,
        name: Map.get(room_data, :name) || Map.get(room_data, "name") || "Untitled Room",
        description: Map.get(room_data, :description) || Map.get(room_data, "description"),
        owner_id: Map.get(room_data, :owner_id) || Map.get(room_data, "owner_id"),
        join_code:
          Map.get(room_data, :join_code) || Map.get(room_data, "join_code") ||
            generate_join_code(),
        is_public: Map.get(room_data, :is_public, Map.get(room_data, "is_public", true)),
        calls_enabled:
          Map.get(room_data, :calls_enabled, Map.get(room_data, "calls_enabled", true)),
        media_playback_enabled:
          Map.get(
            room_data,
            :media_playback_enabled,
            Map.get(room_data, "media_playback_enabled", true)
          ),
        object_3d_enabled:
          Map.get(room_data, :object_3d_enabled, Map.get(room_data, "object_3d_enabled", false)),
        configuration:
          Map.get(room_data, :configuration) || Map.get(room_data, "configuration") || %{},
        members:
          normalize_members(Map.get(room_data, :members) || Map.get(room_data, "members") || %{}),
        sensor_ids: sensor_ids,
        created_at:
          parse_datetime(Map.get(room_data, :created_at) || Map.get(room_data, "created_at")),
        updated_at:
          parse_datetime(Map.get(room_data, :updated_at) || Map.get(room_data, "updated_at"))
      }

      # Update state with the hydrated room
      new_state =
        state
        |> put_in([Access.key(:rooms), room_id], room)
        |> put_in([Access.key(:join_codes), room.join_code], room_id)
        |> hydrate_user_rooms(room.members, room_id)

      Logger.debug("[RoomStore] Hydrated room #{room_id}")
      {:reply, :ok, new_state}
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp generate_join_code(length \\ 8) do
    alphabet = ~c"ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

    1..length
    |> Enum.map(fn _ -> Enum.random(alphabet) end)
    |> List.to_string()
  end

  defp update_user_rooms(state, user_id, room_id, :add) do
    update_in(state, [Access.key(:user_rooms), Access.key(user_id, [])], fn rooms ->
      if room_id in rooms, do: rooms, else: [room_id | rooms]
    end)
  end

  defp update_user_rooms(state, user_id, room_id, :remove) do
    update_in(state, [Access.key(:user_rooms), Access.key(user_id, [])], fn rooms ->
      List.delete(rooms, room_id)
    end)
  end

  defp remove_room_from_all_users(state, room_id, members) do
    Enum.reduce(Map.keys(members), state, fn user_id, acc ->
      update_user_rooms(acc, user_id, room_id, :remove)
    end)
  end

  defp maybe_update(map, key, attrs) do
    case Map.fetch(attrs, key) do
      {:ok, value} -> Map.put(map, key, value)
      :error -> map
    end
  end

  defp broadcast_room_update(room_id, message) do
    # Broadcast to room-specific topic (for LiveViews watching this room)
    Phoenix.PubSub.broadcast(Sensocto.PubSub, "room:#{room_id}", {:room_update, message})
  end

  defp broadcast_cluster_room_created(room_id) do
    Phoenix.PubSub.broadcast(Sensocto.PubSub, "rooms:cluster", {:room_created, room_id, node()})
  end

  defp broadcast_cluster_room_deleted(room_id) do
    Phoenix.PubSub.broadcast(Sensocto.PubSub, "rooms:cluster", {:room_deleted, room_id, node()})
  end

  defp broadcast_cluster_room_sync(room) do
    # Convert MapSet to list for PubSub serialization
    room_for_broadcast =
      Map.update(room, :sensor_ids, [], fn
        %MapSet{} = set -> MapSet.to_list(set)
        list when is_list(list) -> list
        _ -> []
      end)

    Phoenix.PubSub.broadcast(
      Sensocto.PubSub,
      "rooms:cluster",
      {:room_state_sync, room_for_broadcast, node()}
    )
  end

  # ============================================================================
  # Async Iroh Sync
  # ============================================================================

  defp async_sync_room(room, true = _iroh_available) do
    # Convert MapSet to list for JSON serialization
    room_for_storage = Map.update(room, :sensor_ids, [], &MapSet.to_list/1)

    Task.Supervisor.start_child(Sensocto.TaskSupervisor, fn ->
      case IrohStore.store_room(room_for_storage) do
        {:ok, _hash} ->
          Logger.debug("[RoomStore] Synced room #{room.id} to iroh")

        {:error, reason} ->
          Logger.warning("[RoomStore] Failed to sync room to iroh: #{inspect(reason)}")
      end
    end)
  end

  defp async_sync_room(_room, false), do: :ok

  defp async_delete_room(room_id, true = _iroh_available) do
    Task.Supervisor.start_child(Sensocto.TaskSupervisor, fn ->
      case IrohStore.delete_room(room_id) do
        :ok ->
          Logger.debug("[RoomStore] Deleted room #{room_id} from iroh")

        {:error, reason} ->
          Logger.warning("[RoomStore] Failed to delete room from iroh: #{inspect(reason)}")
      end
    end)
  end

  defp async_delete_room(_room_id, false), do: :ok

  defp async_sync_membership(room_id, user_id, role, true = _iroh_available) do
    Task.Supervisor.start_child(Sensocto.TaskSupervisor, fn ->
      case IrohStore.store_membership(room_id, user_id, role) do
        {:ok, _hash} ->
          Logger.debug("[RoomStore] Synced membership #{room_id}:#{user_id} to iroh")

        {:error, reason} ->
          Logger.warning("[RoomStore] Failed to sync membership to iroh: #{inspect(reason)}")
      end
    end)
  end

  defp async_sync_membership(_room_id, _user_id, _role, false), do: :ok

  defp async_delete_membership(room_id, user_id, true = _iroh_available) do
    Task.Supervisor.start_child(Sensocto.TaskSupervisor, fn ->
      case IrohStore.delete_membership(room_id, user_id) do
        :ok ->
          Logger.debug("[RoomStore] Deleted membership #{room_id}:#{user_id} from iroh")

        {:error, reason} ->
          Logger.warning("[RoomStore] Failed to delete membership from iroh: #{inspect(reason)}")
      end
    end)
  end

  defp async_delete_membership(_room_id, _user_id, false), do: :ok

  # ============================================================================
  # PostgreSQL Sync
  # ============================================================================

  # Creates room and owner membership in sequence (room first, then membership)
  # to avoid FK constraint violation race condition
  defp sync_room_and_owner_to_postgres(room, owner_id) do
    Task.Supervisor.start_child(Sensocto.TaskSupervisor, fn ->
      try do
        # Step 1: Create the room first
        create_room_in_postgres(room)

        # Step 2: Then create owner membership (room now exists)
        create_membership_in_postgres(room.id, owner_id, :owner)
      rescue
        e ->
          Logger.error(
            "[RoomStore] Failed to sync room and owner to PostgreSQL: #{Exception.message(e)}"
          )
      end
    end)
  end

  # Synchronous room creation (called within a Task)
  defp create_room_in_postgres(room) do
    attrs = %{
      id: room.id,
      name: room.name,
      description: room.description,
      owner_id: room.owner_id,
      join_code: room.join_code,
      is_public: room.is_public,
      is_persisted: true,
      calls_enabled: Map.get(room, :calls_enabled, true),
      configuration: room.configuration || %{}
    }

    existing = RoomResource |> Ash.get(room.id, error?: false)

    case existing do
      {:ok, nil} ->
        RoomResource
        |> Ash.Changeset.for_create(:sync_create, attrs)
        |> Ash.create!()

        Logger.debug("[RoomStore] Synced new room #{room.id} to PostgreSQL")

      {:ok, _room} ->
        Logger.debug("[RoomStore] Room #{room.id} already exists in PostgreSQL")

      {:error, _reason} ->
        RoomResource
        |> Ash.Changeset.for_create(:sync_create, attrs)
        |> Ash.create!()

        Logger.debug("[RoomStore] Synced new room #{room.id} to PostgreSQL")
    end
  end

  # Synchronous membership creation (called within a Task)
  defp create_membership_in_postgres(room_id, user_id, role) do
    import Ecto.Query

    {:ok, room_uuid} = Ecto.UUID.dump(room_id)
    {:ok, user_uuid} = Ecto.UUID.dump(user_id)

    existing =
      Sensocto.Repo.one(
        from m in "room_memberships",
          where: m.room_id == ^room_uuid and m.user_id == ^user_uuid,
          select: m.id
      )

    if existing do
      Logger.debug("[RoomStore] Membership #{room_id}:#{user_id} already exists in PostgreSQL")
    else
      RoomMembership
      |> Ash.Changeset.for_create(:sync_create, %{room_id: room_id, user_id: user_id, role: role})
      |> Ash.create!()

      Logger.debug("[RoomStore] Synced membership #{room_id}:#{user_id} to PostgreSQL")
    end
  end

  defp sync_room_to_postgres(room) do
    Task.Supervisor.start_child(Sensocto.TaskSupervisor, fn ->
      try do
        create_room_in_postgres(room)
      rescue
        e ->
          Logger.error("[RoomStore] Failed to sync room to PostgreSQL: #{Exception.message(e)}")
      end
    end)
  end

  defp sync_room_update_to_postgres(room) do
    Task.Supervisor.start_child(Sensocto.TaskSupervisor, fn ->
      try do
        existing = RoomResource |> Ash.get(room.id, error?: false)

        case existing do
          {:ok, record} when not is_nil(record) ->
            record
            |> Ash.Changeset.for_update(:sync_update, %{
              name: room.name,
              description: room.description,
              is_public: room.is_public,
              calls_enabled: Map.get(room, :calls_enabled, true),
              media_playback_enabled: Map.get(room, :media_playback_enabled, true),
              object_3d_enabled: Map.get(room, :object_3d_enabled, false),
              configuration: room.configuration,
              join_code: room.join_code
            })
            |> Ash.update!()

            Logger.debug("[RoomStore] Updated room #{room.id} in PostgreSQL")

          _ ->
            # Room doesn't exist, create it
            sync_room_to_postgres(room)
        end
      rescue
        e ->
          Logger.error("[RoomStore] Failed to update room in PostgreSQL: #{Exception.message(e)}")
      end
    end)
  end

  defp delete_room_from_postgres(room_id) do
    Task.Supervisor.start_child(Sensocto.TaskSupervisor, fn ->
      try do
        case RoomResource |> Ash.get(room_id, error?: false) do
          {:ok, room} when not is_nil(room) ->
            Ash.destroy!(room)
            Logger.debug("[RoomStore] Deleted room #{room_id} from PostgreSQL")

          _ ->
            Logger.debug("[RoomStore] Room #{room_id} not found in PostgreSQL, skipping delete")
        end
      rescue
        e ->
          Logger.error(
            "[RoomStore] Failed to delete room from PostgreSQL: #{Exception.message(e)}"
          )
      end
    end)
  end

  defp sync_membership_to_postgres(room_id, user_id, role) do
    Task.Supervisor.start_child(Sensocto.TaskSupervisor, fn ->
      try do
        # Check if membership exists using Ash
        import Ecto.Query

        # Convert string UUIDs to binary for raw query
        {:ok, room_uuid} = Ecto.UUID.dump(room_id)
        {:ok, user_uuid} = Ecto.UUID.dump(user_id)

        existing =
          Sensocto.Repo.one(
            from m in "room_memberships",
              where: m.room_id == ^room_uuid and m.user_id == ^user_uuid,
              select: m.id
          )

        if existing do
          Logger.debug(
            "[RoomStore] Membership #{room_id}:#{user_id} already exists in PostgreSQL"
          )
        else
          RoomMembership
          |> Ash.Changeset.for_create(:sync_create, %{
            room_id: room_id,
            user_id: user_id,
            role: role
          })
          |> Ash.create!()

          Logger.debug("[RoomStore] Synced membership #{room_id}:#{user_id} to PostgreSQL")
        end
      rescue
        e ->
          Logger.error(
            "[RoomStore] Failed to sync membership to PostgreSQL: #{Exception.message(e)}"
          )
      end
    end)
  end

  defp delete_membership_from_postgres(room_id, user_id) do
    Task.Supervisor.start_child(Sensocto.TaskSupervisor, fn ->
      try do
        import Ecto.Query

        # Convert string UUIDs to binary for raw query
        {:ok, room_uuid} = Ecto.UUID.dump(room_id)
        {:ok, user_uuid} = Ecto.UUID.dump(user_id)

        Sensocto.Repo.delete_all(
          from m in "room_memberships",
            where: m.room_id == ^room_uuid and m.user_id == ^user_uuid
        )

        Logger.debug("[RoomStore] Deleted membership #{room_id}:#{user_id} from PostgreSQL")
      rescue
        e ->
          Logger.error("[RoomStore] Failed to delete membership from PostgreSQL: #{inspect(e)}")
      end
    end)
  end

  defp update_membership_role_in_postgres(room_id, user_id, new_role) do
    Task.Supervisor.start_child(Sensocto.TaskSupervisor, fn ->
      try do
        import Ecto.Query

        # Convert string UUIDs to binary for raw query
        {:ok, room_uuid} = Ecto.UUID.dump(room_id)
        {:ok, user_uuid} = Ecto.UUID.dump(user_id)

        role_string = Atom.to_string(new_role)
        now = DateTime.utc_now()

        Sensocto.Repo.update_all(
          from(m in "room_memberships",
            where: m.room_id == ^room_uuid and m.user_id == ^user_uuid
          ),
          set: [role: role_string, updated_at: now]
        )

        Logger.debug(
          "[RoomStore] Updated membership role #{room_id}:#{user_id} to #{new_role} in PostgreSQL"
        )
      rescue
        e ->
          Logger.error(
            "[RoomStore] Failed to update membership role in PostgreSQL: #{inspect(e)}"
          )
      end
    end)
  end

  # ============================================================================
  # Hydration Helpers
  # ============================================================================

  defp build_members_map(room) do
    # Build members map from room_memberships
    # Always include owner
    base = %{room.owner_id => :owner}

    case room.room_memberships do
      memberships when is_list(memberships) ->
        Enum.reduce(memberships, base, fn membership, acc ->
          Map.put(acc, membership.user_id, membership.role)
        end)

      _ ->
        base
    end
  end

  defp normalize_members(members) when is_map(members) do
    Map.new(members, fn {user_id, role} ->
      normalized_role =
        case role do
          r when is_atom(r) -> r
          "owner" -> :owner
          "admin" -> :admin
          "member" -> :member
          _ -> :member
        end

      {user_id, normalized_role}
    end)
  end

  defp normalize_members(_), do: %{}

  defp parse_datetime(nil), do: DateTime.utc_now()

  defp parse_datetime(%DateTime{} = dt), do: dt

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} -> dt
      _ -> DateTime.utc_now()
    end
  end

  defp parse_datetime(_), do: DateTime.utc_now()

  defp hydrate_user_rooms(state, members, room_id) do
    Enum.reduce(Map.keys(members), state, fn user_id, acc ->
      update_user_rooms(acc, user_id, room_id, :add)
    end)
  end
end
