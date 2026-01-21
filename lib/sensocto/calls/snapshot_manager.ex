defmodule Sensocto.Calls.SnapshotManager do
  @moduledoc """
  Manages snapshot mode for non-attentive call participants.

  When participants are in :viewer or :idle tier, they switch from
  continuous video streams to periodic JPEG snapshots, dramatically
  reducing bandwidth usage while maintaining visual presence.

  ## How It Works

  1. Clients in snapshot mode capture periodic JPEG frames from their video
  2. Snapshots are sent via the Phoenix Channel (not WebRTC media track)
  3. This module stores the latest snapshot per user for late joiners
  4. Receivers display snapshots as static images instead of video

  ## Snapshot Intervals

  - :viewer tier - 1000ms (1 fps) for passive watchers
  - :idle tier - 5000ms (0.2 fps) for AFK/hidden tab users

  ## Memory Management

  Snapshots are stored in ETS for fast concurrent access.
  Old snapshots are automatically cleaned up when:
  - User leaves the call
  - User upgrades to video tier (:active or :recent)
  - TTL expires (configurable, default 60 seconds)
  """

  use GenServer
  require Logger

  alias Sensocto.Calls.QualityManager

  @table_name :call_snapshots
  @cleanup_interval_ms 30_000
  @default_ttl_ms 60_000

  # Snapshot data structure
  defstruct [
    :user_id,
    :room_id,
    # Base64 JPEG data
    :data,
    :width,
    :height,
    # When captured
    :timestamp,
    # When server received it
    :received_at
  ]

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Stores a snapshot for a participant.
  Called when receiving snapshot data from the client via channel.
  """
  @spec store_snapshot(String.t(), String.t(), map()) :: :ok
  def store_snapshot(room_id, user_id, snapshot_data) do
    snapshot = %__MODULE__{
      user_id: user_id,
      room_id: room_id,
      data: snapshot_data["data"],
      width: snapshot_data["width"] || 320,
      height: snapshot_data["height"] || 240,
      timestamp: snapshot_data["timestamp"] || System.system_time(:millisecond),
      received_at: System.monotonic_time(:millisecond)
    }

    :ets.insert(@table_name, {{room_id, user_id}, snapshot})
    :ok
  end

  @doc """
  Retrieves the latest snapshot for a participant.
  Returns nil if no snapshot exists or if it's expired.
  """
  @spec get_snapshot(String.t(), String.t()) :: map() | nil
  def get_snapshot(room_id, user_id) do
    case :ets.lookup(@table_name, {room_id, user_id}) do
      [{{^room_id, ^user_id}, snapshot}] ->
        if snapshot_valid?(snapshot) do
          format_snapshot(snapshot)
        else
          # Clean up expired snapshot
          :ets.delete(@table_name, {room_id, user_id})
          nil
        end

      [] ->
        nil
    end
  end

  @doc """
  Retrieves all snapshots for a room.
  Useful for late joiners to get current state of all snapshot-mode participants.
  """
  @spec get_room_snapshots(String.t()) :: [map()]
  def get_room_snapshots(room_id) do
    match_spec = [{{{room_id, :"$1"}, :"$2"}, [], [:"$2"]}]

    :ets.select(@table_name, match_spec)
    |> Enum.filter(&snapshot_valid?/1)
    |> Enum.map(&format_snapshot/1)
  end

  @doc """
  Removes snapshot for a participant.
  Called when user leaves call or upgrades to video tier.
  """
  @spec remove_snapshot(String.t(), String.t()) :: :ok
  def remove_snapshot(room_id, user_id) do
    :ets.delete(@table_name, {room_id, user_id})
    :ok
  end

  @doc """
  Removes all snapshots for a room.
  Called when call ends.
  """
  @spec clear_room_snapshots(String.t()) :: :ok
  def clear_room_snapshots(room_id) do
    match_spec = [{{{room_id, :"$1"}, :_}, [], [true]}]
    :ets.select_delete(@table_name, match_spec)
    :ok
  end

  @doc """
  Returns the recommended snapshot interval for a tier in milliseconds.
  Returns nil for tiers that don't use snapshots.
  """
  @spec get_interval_for_tier(atom()) :: non_neg_integer() | nil
  def get_interval_for_tier(tier) do
    QualityManager.get_snapshot_interval(tier)
  end

  @doc """
  Checks if a tier uses snapshot mode.
  """
  @spec snapshot_tier?(atom()) :: boolean()
  def snapshot_tier?(tier) do
    QualityManager.get_tier_mode(tier) == :snapshot
  end

  @doc """
  Returns snapshot configuration for the client.
  Includes interval, dimensions, and quality settings.
  """
  @spec get_snapshot_config(atom()) :: map()
  def get_snapshot_config(tier) do
    profile = QualityManager.get_tier_profile(tier)

    %{
      enabled: profile.mode == :snapshot,
      interval_ms: Map.get(profile, :interval_ms, 1000),
      width: Map.get(profile, :width, 320),
      height: Map.get(profile, :height, 240),
      jpeg_quality: Map.get(profile, :jpeg_quality, 70)
    }
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Create ETS table for snapshot storage
    :ets.new(@table_name, [
      :set,
      :public,
      :named_table,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ])

    # Schedule periodic cleanup
    schedule_cleanup()

    {:ok, %{ttl_ms: @default_ttl_ms}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_expired_snapshots(state.ttl_ms)
    schedule_cleanup()
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("SnapshotManager received unknown message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private Functions

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
  end

  defp cleanup_expired_snapshots(ttl_ms) do
    now = System.monotonic_time(:millisecond)
    cutoff = now - ttl_ms

    # Delete all snapshots older than TTL
    match_spec = [
      {
        {:_, %{received_at: :"$1"}},
        [{:<, :"$1", cutoff}],
        [true]
      }
    ]

    deleted = :ets.select_delete(@table_name, match_spec)

    if deleted > 0 do
      Logger.debug("SnapshotManager cleaned up #{deleted} expired snapshots")
    end
  end

  defp snapshot_valid?(snapshot) do
    now = System.monotonic_time(:millisecond)
    age = now - snapshot.received_at
    age < @default_ttl_ms
  end

  defp format_snapshot(snapshot) do
    %{
      user_id: snapshot.user_id,
      room_id: snapshot.room_id,
      data: snapshot.data,
      width: snapshot.width,
      height: snapshot.height,
      timestamp: snapshot.timestamp
    }
  end
end
