defmodule Sensocto.Resilience.CircuitBreaker do
  @moduledoc """
  Lightweight ETS-backed circuit breaker for external service calls.

  ## States

  - `:closed` - Normal operation, calls pass through
  - `:open` - Failures exceeded threshold, calls rejected immediately
  - `:half_open` - Timeout elapsed, one probe call allowed

  ## Failure Decay

  Failures decay over time with a configurable half-life (default 60s).
  This prevents old failures from permanently degrading a breaker:
  4 failures from 2 minutes ago + 1 new failure = ~2 effective failures, not 5.

  ## Usage

      case CircuitBreaker.call(:iroh_nif, fn -> expensive_nif_call() end) do
        {:ok, result} -> handle_result(result)
        {:error, :circuit_open} -> fallback()
        {:error, reason} -> handle_error(reason)
      end
  """

  @table :circuit_breakers

  # Failures halve every 60 seconds
  @decay_half_life_ms 60_000

  @type breaker_name :: atom()
  @type state :: :closed | :open | :half_open

  @doc """
  Executes `fun` through the named circuit breaker.

  Returns `{:ok, result}` on success, `{:error, :circuit_open}` when open,
  or `{:error, reason}` on failure (which also counts toward the threshold).
  """
  @spec call(breaker_name(), (-> term())) :: {:ok, term()} | {:error, term()}
  def call(name, fun) do
    case get_state(name) do
      :open ->
        {:error, :circuit_open}

      state when state in [:closed, :half_open] ->
        try do
          result = fun.()
          record_success(name)
          {:ok, result}
        rescue
          e ->
            record_failure(name)
            {:error, e}
        catch
          kind, reason ->
            record_failure(name)
            {:error, {kind, reason}}
        end
    end
  end

  @doc """
  Returns the current state of a circuit breaker.
  """
  @spec get_state(breaker_name()) :: state()
  def get_state(name) do
    case :ets.lookup(@table, name) do
      [{^name, :open, _failures, _threshold, timeout_ms, opened_at, _last_failure_at}]
      when is_integer(opened_at) ->
        if System.monotonic_time(:millisecond) - opened_at >= timeout_ms,
          do: :half_open,
          else: :open

      [{^name, breaker_state, _failures, _threshold, _timeout_ms, _opened_at, _last_failure_at}] ->
        breaker_state

      [] ->
        :closed
    end
  rescue
    ArgumentError -> :closed
  end

  @doc """
  Manually resets a circuit breaker to closed state.
  """
  @spec reset(breaker_name()) :: :ok
  def reset(name) do
    case :ets.lookup(@table, name) do
      [{^name, _state, _failures, threshold, timeout_ms, _opened_at, _last_failure_at}] ->
        :ets.insert(@table, {name, :closed, 0, threshold, timeout_ms, nil, nil})
        :ok

      [] ->
        :ok
    end
  rescue
    ArgumentError -> :ok
  end

  @doc """
  Returns a map of all breaker names to their current states.
  """
  @spec get_all_states() :: %{breaker_name() => state()}
  def get_all_states do
    :ets.tab2list(@table)
    |> Enum.map(fn {name, _state, _failures, _threshold, _timeout_ms, _opened_at,
                    _last_failure_at} ->
      {name, get_state(name)}
    end)
    |> Map.new()
  rescue
    ArgumentError -> %{}
  end

  @doc false
  def register(name, threshold, timeout_ms) do
    :ets.insert(@table, {name, :closed, 0, threshold, timeout_ms, nil, nil})
  end

  # -- Internal --

  defp record_success(name) do
    case :ets.lookup(@table, name) do
      [{^name, state, _failures, threshold, timeout_ms, _opened_at, _last_failure_at}]
      when state in [:half_open, :closed] ->
        :ets.insert(@table, {name, :closed, 0, threshold, timeout_ms, nil, nil})

      _ ->
        :ok
    end
  rescue
    ArgumentError -> :ok
  end

  defp record_failure(name) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, name) do
      [{^name, :half_open, _failures, threshold, timeout_ms, _opened_at, _last_failure_at}] ->
        # Probe failed, go back to open
        :ets.insert(@table, {name, :open, threshold, threshold, timeout_ms, now, now})

      [{^name, :closed, failures, threshold, timeout_ms, _opened_at, last_failure_at}] ->
        decayed = decay_failures(failures, last_failure_at, now)
        new_failures = decayed + 1

        if new_failures >= threshold do
          :ets.insert(@table, {name, :open, new_failures, threshold, timeout_ms, now, now})
        else
          :ets.insert(@table, {name, :closed, new_failures, threshold, timeout_ms, nil, now})
        end

      _ ->
        :ok
    end
  rescue
    ArgumentError -> :ok
  end

  defp decay_failures(_failures, nil, _now), do: 0

  defp decay_failures(failures, last_failure_at, now) when failures > 0 do
    elapsed = now - last_failure_at
    (failures * :math.pow(0.5, elapsed / @decay_half_life_ms)) |> trunc()
  end

  defp decay_failures(_failures, _last_failure_at, _now), do: 0
end
