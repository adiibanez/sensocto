defmodule Sensocto.Lenses.Supervisor do
  @moduledoc """
  Supervisor for the adaptive data lenses infrastructure.

  Lenses transform sensor data streams based on client capabilities and needs:
  - ThrottledLens: Rate-limits data to configurable Hz (e.g., 5, 10, 20 Hz)
  - PriorityLens: Adapts fidelity based on attention level and client health

  ## Architecture

  ```
  Lenses.Supervisor (:one_for_one)
    |-- LensRouter (subscribes to all sensor data, routes to lenses)
    |-- ThrottledLens (rate-limited stream)
    |-- PriorityLens (attention-based adaptive stream)
  ```

  LiveViews subscribe to lens topics instead of individual sensor topics,
  dramatically reducing subscription count and enabling adaptive streaming.
  """

  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      # Router receives all sensor data and distributes to appropriate lenses
      Sensocto.Lenses.Router,

      # ThrottledLens: Rate-limited streams at various frequencies
      {Sensocto.Lenses.ThrottledLens, name: Sensocto.Lenses.ThrottledLens},

      # PriorityLens: Per-socket adaptive streams based on attention + client health
      {Sensocto.Lenses.PriorityLens, name: Sensocto.Lenses.PriorityLens}
    ]

    Supervisor.init(children, strategy: :one_for_one, max_restarts: 5, max_seconds: 10)
  end
end
