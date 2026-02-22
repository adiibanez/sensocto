defmodule Sensocto.Bio.Supervisor do
  @moduledoc """
  Supervisor for all biomimetic components.

  Manages the lifecycle of:
  - NoveltyDetector (Locus Coeruleus)
  - PredictiveLoadBalancer (Cerebellum)
  - HomeostaticTuner (Synaptic Plasticity)
  - ResourceArbiter (Lateral Inhibition)
  - CircadianScheduler (SCN)
  - SyncComputer (Phase Synchronization)
  - CorrelationTracker (Hebbian Learning)
  """

  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      Sensocto.Bio.CorrelationTracker,
      Sensocto.Bio.NoveltyDetector,
      Sensocto.Bio.PredictiveLoadBalancer,
      Sensocto.Bio.HomeostaticTuner,
      Sensocto.Bio.ResourceArbiter,
      Sensocto.Bio.CircadianScheduler,
      Sensocto.Bio.SyncComputer
    ]

    Supervisor.init(children, strategy: :one_for_one, max_restarts: 10, max_seconds: 60)
  end
end
