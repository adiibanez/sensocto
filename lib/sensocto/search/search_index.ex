defmodule Sensocto.Search.SearchIndex do
  @moduledoc """
  GenServer-based in-memory search index for fast lookups across sensors and rooms.
  Uses prefix-based indexing for autocomplete functionality.
  """
  use GenServer
  require Logger

  alias Sensocto.SensorsDynamicSupervisor
  alias Sensocto.SimpleSensor
  alias Sensocto.RoomStore
  alias Sensocto.Accounts.User

  @refresh_interval :timer.seconds(30)

  defstruct sensors: %{}, rooms: %{}, users: %{}, prefixes: %{}

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Search for sensors and rooms matching the query.
  Returns results grouped by type with relevance scoring.
  """
  def search(query) when is_binary(query) and byte_size(query) > 0 do
    GenServer.call(__MODULE__, {:search, String.downcase(query)})
  end

  def search(_), do: %{sensors: [], rooms: [], users: []}

  @doc """
  Index a sensor for search.
  """
  def index_sensor(sensor_id, sensor_data) do
    GenServer.cast(__MODULE__, {:index_sensor, sensor_id, sensor_data})
  end

  @doc """
  Remove a sensor from the index.
  """
  def remove_sensor(sensor_id) do
    GenServer.cast(__MODULE__, {:remove_sensor, sensor_id})
  end

  @doc """
  Index a room for search.
  """
  def index_room(room_id, room_data) do
    GenServer.cast(__MODULE__, {:index_room, room_id, room_data})
  end

  @doc """
  Remove a room from the index.
  """
  def remove_room(room_id) do
    GenServer.cast(__MODULE__, {:remove_room, room_id})
  end

  @doc """
  Force a full reindex of all sensors and rooms.
  """
  def reindex do
    GenServer.cast(__MODULE__, :reindex)
  end

  @doc """
  Get current index stats.
  """
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  @impl true
  def init(_opts) do
    Logger.info("[SearchIndex] Starting search index")
    schedule_refresh()
    send(self(), :initial_index)
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call({:search, query}, _from, state) do
    results = perform_search(query, state)
    {:reply, results, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      sensors_count: map_size(state.sensors),
      rooms_count: map_size(state.rooms),
      users_count: map_size(state.users),
      prefixes_count: map_size(state.prefixes)
    }
    {:reply, stats, state}
  end

  @impl true
  def handle_cast({:index_sensor, sensor_id, sensor_data}, state) do
    new_state = do_index_sensor(state, sensor_id, sensor_data)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:remove_sensor, sensor_id}, state) do
    new_state = do_remove_sensor(state, sensor_id)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:index_room, room_id, room_data}, state) do
    new_state = do_index_room(state, room_id, room_data)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:remove_room, room_id}, state) do
    new_state = do_remove_room(state, room_id)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:reindex, state) do
    new_state = do_full_reindex(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:initial_index, state) do
    new_state = do_full_reindex(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:refresh, state) do
    schedule_refresh()
    new_state = do_full_reindex(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(_, state), do: {:noreply, state}

  defp schedule_refresh do
    Process.send_after(self(), :refresh, @refresh_interval)
  end

  defp do_full_reindex(_state) do
    sensors = index_all_sensors()
    rooms = index_all_rooms()
    users = index_all_users()
    prefixes = build_prefix_index(sensors, rooms, users)

    Logger.debug("[SearchIndex] Reindexed #{map_size(sensors)} sensors, #{map_size(rooms)} rooms, #{map_size(users)} users")

    %__MODULE__{
      sensors: sensors,
      rooms: rooms,
      users: users,
      prefixes: prefixes
    }
  end

  defp index_all_sensors do
    SensorsDynamicSupervisor.get_device_names()
    |> Enum.reduce(%{}, fn sensor_id, acc ->
      case fetch_sensor_data(sensor_id) do
        {:ok, data} -> Map.put(acc, sensor_id, data)
        :error -> acc
      end
    end)
  end

  defp fetch_sensor_data(sensor_id) do
    try do
      state = SimpleSensor.get_view_state(sensor_id)
      {:ok, %{
        id: sensor_id,
        name: state.sensor_name || sensor_id,
        type: state.sensor_type || "unknown",
        attributes: Map.keys(state.attributes || %{}),
        searchable: build_searchable_text(state.sensor_name, state.sensor_type, sensor_id)
      }}
    catch
      :exit, _ -> :error
    end
  end

  defp index_all_rooms do
    RoomStore.list_all_rooms()
    |> Enum.reduce(%{}, fn room, acc ->
      room_data = %{
        id: room.id,
        name: room.name || room.id,
        description: room.description,
        is_public: room.is_public,
        searchable: build_searchable_text(room.name, room.description, room.id)
      }
      Map.put(acc, room.id, room_data)
    end)
  end

  defp index_all_users do
    case Ash.read(User, authorize?: false) do
      {:ok, users} ->
        Enum.reduce(users, %{}, fn user, acc ->
          email = to_string(user.email)
          user_data = %{
            id: user.id,
            email: email,
            name: email_to_name(email),
            searchable: String.downcase(email)
          }
          Map.put(acc, user.id, user_data)
        end)

      _ ->
        %{}
    end
  end

  defp email_to_name(email) do
    email
    |> String.split("@")
    |> List.first()
    |> String.replace(~r/[._-]/, " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp build_searchable_text(name, type_or_desc, id) do
    [name, type_or_desc, id]
    |> Enum.filter(&is_binary/1)
    |> Enum.join(" ")
    |> String.downcase()
  end

  defp build_prefix_index(sensors, rooms, users) do
    sensor_prefixes = build_prefixes_for_items(sensors, :sensor)
    room_prefixes = build_prefixes_for_items(rooms, :room)
    user_prefixes = build_prefixes_for_items(users, :user)
    sensor_prefixes
    |> merge_prefix_maps(room_prefixes)
    |> merge_prefix_maps(user_prefixes)
  end

  defp build_prefixes_for_items(items, type) do
    Enum.reduce(items, %{}, fn {id, data}, acc ->
      words = extract_words(data.searchable)
      Enum.reduce(words, acc, fn word, word_acc ->
        prefixes = generate_prefixes(word, 1, 10)
        Enum.reduce(prefixes, word_acc, fn prefix, prefix_acc ->
          existing = Map.get(prefix_acc, prefix, [])
          Map.put(prefix_acc, prefix, [{type, id} | existing])
        end)
      end)
    end)
  end

  defp extract_words(text) when is_binary(text) do
    text
    |> String.split(~r/[\s\-_.:]+/, trim: true)
    |> Enum.filter(&(String.length(&1) >= 1))
  end

  defp extract_words(_), do: []

  defp generate_prefixes(word, min_len, max_len) do
    word_len = String.length(word)
    max_prefix_len = min(word_len, max_len)

    for len <- min_len..max_prefix_len do
      String.slice(word, 0, len)
    end
  end

  defp merge_prefix_maps(map1, map2) do
    Map.merge(map1, map2, fn _k, v1, v2 -> v1 ++ v2 end)
  end

  defp do_index_sensor(state, sensor_id, sensor_data) do
    data = %{
      id: sensor_id,
      name: sensor_data[:name] || sensor_id,
      type: sensor_data[:type] || "unknown",
      attributes: sensor_data[:attributes] || [],
      searchable: build_searchable_text(
        sensor_data[:name],
        sensor_data[:type],
        sensor_id
      )
    }

    new_sensors = Map.put(state.sensors, sensor_id, data)
    new_prefixes = build_prefix_index(new_sensors, state.rooms, state.users)

    %{state | sensors: new_sensors, prefixes: new_prefixes}
  end

  defp do_remove_sensor(state, sensor_id) do
    new_sensors = Map.delete(state.sensors, sensor_id)
    new_prefixes = build_prefix_index(new_sensors, state.rooms, state.users)
    %{state | sensors: new_sensors, prefixes: new_prefixes}
  end

  defp do_index_room(state, room_id, room_data) do
    data = %{
      id: room_id,
      name: room_data[:name] || room_id,
      description: room_data[:description],
      is_public: room_data[:is_public] || false,
      searchable: build_searchable_text(
        room_data[:name],
        room_data[:description],
        room_id
      )
    }

    new_rooms = Map.put(state.rooms, room_id, data)
    new_prefixes = build_prefix_index(state.sensors, new_rooms, state.users)

    %{state | rooms: new_rooms, prefixes: new_prefixes}
  end

  defp do_remove_room(state, room_id) do
    new_rooms = Map.delete(state.rooms, room_id)
    new_prefixes = build_prefix_index(state.sensors, new_rooms, state.users)
    %{state | rooms: new_rooms, prefixes: new_prefixes}
  end

  defp perform_search(query, state) do
    query_words = extract_words(query)

    if Enum.empty?(query_words) do
      %{sensors: [], rooms: [], users: []}
    else
      candidates = find_candidates(query_words, state.prefixes)

      sensors =
        candidates
        |> Enum.filter(fn {type, _id} -> type == :sensor end)
        |> Enum.map(fn {:sensor, id} -> Map.get(state.sensors, id) end)
        |> Enum.filter(&(&1 != nil))
        |> Enum.map(fn sensor -> score_result(sensor, query) end)
        |> Enum.sort_by(fn {_sensor, score} -> -score end)
        |> Enum.take(10)
        |> Enum.map(fn {sensor, _score} -> sensor end)

      rooms =
        candidates
        |> Enum.filter(fn {type, _id} -> type == :room end)
        |> Enum.map(fn {:room, id} -> Map.get(state.rooms, id) end)
        |> Enum.filter(&(&1 != nil))
        |> Enum.map(fn room -> score_result(room, query) end)
        |> Enum.sort_by(fn {_room, score} -> -score end)
        |> Enum.take(10)
        |> Enum.map(fn {room, _score} -> room end)

      users =
        candidates
        |> Enum.filter(fn {type, _id} -> type == :user end)
        |> Enum.map(fn {:user, id} -> Map.get(state.users, id) end)
        |> Enum.filter(&(&1 != nil))
        |> Enum.map(fn user -> score_result(user, query) end)
        |> Enum.sort_by(fn {_user, score} -> -score end)
        |> Enum.take(10)
        |> Enum.map(fn {user, _score} -> user end)

      %{sensors: sensors, rooms: rooms, users: users}
    end
  end

  defp find_candidates(query_words, prefixes) do
    query_words
    |> Enum.flat_map(fn word ->
      Map.get(prefixes, word, [])
    end)
    |> Enum.uniq()
  end

  defp score_result(item, query) do
    name = String.downcase(item.name || "")
    searchable = item.searchable || ""

    score = cond do
      name == query -> 100
      String.starts_with?(name, query) -> 80
      String.contains?(name, query) -> 60
      String.starts_with?(searchable, query) -> 40
      String.contains?(searchable, query) -> 20
      true -> 10
    end

    {item, score}
  end
end
