defmodule Sensocto.Payloads.BatteryPayload do
  @moduledoc """
  Battery status payload.

  Contains battery level (0-100%) and charging status.

  ## Example

      iex> BatteryPayload.from_map(%{"level" => 75, "charging" => "yes"})
      {:ok, %BatteryPayload{level: 75, charging: true}}
  """

  @type t :: %__MODULE__{
          level: 0..100,
          charging: boolean(),
          voltage: float() | nil
        }

  @enforce_keys [:level]
  defstruct [:level, charging: false, voltage: nil]

  @doc """
  Creates a BatteryPayload from a map.

  ## Required fields
  - "level" - Battery percentage (0-100)

  ## Optional fields
  - "charging" - Whether the battery is charging ("yes"/true or "no"/false)
  - "voltage" - Battery voltage in volts
  """
  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(%{"level" => level} = params)
      when is_integer(level) and level >= 0 and level <= 100 do
    {:ok,
     %__MODULE__{
       level: level,
       charging: parse_charging(Map.get(params, "charging")),
       voltage: get_float(params, "voltage")
     }}
  end

  def from_map(%{level: level} = params) when is_integer(level) do
    from_map(%{
      "level" => level,
      "charging" => Map.get(params, :charging),
      "voltage" => Map.get(params, :voltage)
    })
  end

  def from_map(%{"level" => level} = params) when is_float(level) do
    from_map(Map.put(params, "level", round(level)))
  end

  def from_map(_), do: {:error, :invalid_battery_payload}

  @doc """
  Returns true if battery is low (below 20%).
  """
  @spec low?(t()) :: boolean()
  def low?(%__MODULE__{level: level}), do: level < 20

  @doc """
  Returns true if battery is critical (below 10%).
  """
  @spec critical?(t()) :: boolean()
  def critical?(%__MODULE__{level: level}), do: level < 10

  defp parse_charging("yes"), do: true
  defp parse_charging("no"), do: false
  defp parse_charging(true), do: true
  defp parse_charging(false), do: false
  defp parse_charging(1), do: true
  defp parse_charging(0), do: false
  defp parse_charging(_), do: false

  defp get_float(map, key) do
    case Map.get(map, key) do
      n when is_number(n) -> n / 1
      _ -> nil
    end
  end

  defimpl Sensocto.Protocols.AttributePayload do
    def validate(%Sensocto.Payloads.BatteryPayload{level: l}) when l >= 0 and l <= 100 do
      {:ok, @for}
    end

    def validate(_), do: {:error, :invalid_battery_level}

    def display_value(%{level: level, charging: charging}) do
      charging_str = if charging, do: " (charging)", else: ""
      "#{level}%#{charging_str}"
    end

    def render_hints(%{level: level, charging: charging}) do
      %{
        component: "BatteryMeter",
        chart_type: :gauge,
        icon: if(charging, do: "bolt", else: "bolt-slash"),
        color: battery_color(level),
        low: level < 33,
        high: level > 66
      }
    end

    defp battery_color(level) when level < 20, do: "#ff4444"
    defp battery_color(level) when level < 50, do: "#ffaa00"
    defp battery_color(_), do: "#44ff44"
  end
end
