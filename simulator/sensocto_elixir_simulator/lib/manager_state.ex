defmodule Sensocto.Simulator.Manager.State do
  @moduledoc """
  State schema for Manager configuration
  """

  defstruct [:connectors, :config_path]

  @type t :: %__MODULE__{
          # Map of connector_id => connector config
          connectors: map(),
          config_path: String.t()
        }
end
