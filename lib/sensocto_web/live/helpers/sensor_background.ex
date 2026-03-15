defmodule SensoctoWeb.LiveHelpers.SensorBackground do
  @moduledoc """
  Shared helper for sensor background animation data tracking.
  Manages sensor activity accumulation, decay, and push_event delivery.
  Used by CustomSignInLive and IndexLive.
  """

  @bg_tick_interval 800
  @bg_topics ["data:attention:high", "data:attention:medium", "sensors:global"]

  def subscribe do
    for topic <- @bg_topics do
      Phoenix.PubSub.subscribe(Sensocto.PubSub, topic)
    end
  end

  def unsubscribe do
    for topic <- @bg_topics do
      Phoenix.PubSub.unsubscribe(Sensocto.PubSub, topic)
    end
  end

  def start_bg_tick do
    Process.send_after(self(), :bg_tick, @bg_tick_interval)
  end

  def init_activity do
    sensor_ids = Sensocto.SensorsDynamicSupervisor.get_device_names()

    Map.new(sensor_ids, fn id ->
      {id, %{name: id, hit_count: 0, last_ts: System.monotonic_time(:millisecond)}}
    end)
  end

  def handle_measurement(activity, sensor_id) do
    now = System.monotonic_time(:millisecond)

    Map.update(
      activity,
      sensor_id,
      %{name: sensor_id, hit_count: 1, last_ts: now},
      fn entry -> %{entry | hit_count: entry.hit_count + 1, last_ts: now} end
    )
  end

  def handle_measurements_batch(activity, sensor_id, count) do
    now = System.monotonic_time(:millisecond)

    Map.update(
      activity,
      sensor_id,
      %{name: sensor_id, hit_count: count, last_ts: now},
      fn entry -> %{entry | hit_count: entry.hit_count + count, last_ts: now} end
    )
  end

  def handle_sensor_online(activity, sensor_id) do
    Map.put_new(activity, sensor_id, %{
      name: sensor_id,
      hit_count: 0,
      last_ts: System.monotonic_time(:millisecond)
    })
  end

  def handle_sensor_offline(activity, sensor_id) do
    Map.delete(activity, sensor_id)
  end

  @doc """
  Compute top-N sensors by activity, return payload + decayed activity.
  Returns `{sensors_payload, decayed_activity}`.
  """
  def compute_tick(activity, n) do
    top_n =
      activity
      |> Enum.sort_by(fn {_, v} -> v.hit_count end, :desc)
      |> Enum.take(n)

    max_activity =
      case top_n do
        [] -> 1
        list -> max(1, list |> Enum.map(fn {_, v} -> v.hit_count end) |> Enum.max())
      end

    sensors =
      Enum.map(top_n, fn {id, v} ->
        %{id: id, name: v.name, intensity: v.hit_count / max_activity}
      end)

    decayed =
      Map.new(activity, fn {id, v} ->
        {id, %{v | hit_count: div(v.hit_count, 2)}}
      end)

    {sensors, decayed}
  end
end
