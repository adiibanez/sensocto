defprotocol Sensocto.Protocols.AttributePayload do
  @moduledoc """
  Protocol for polymorphic attribute payload handling.

  This protocol enables type-specific validation, display, and rendering
  for different attribute payloads. Each payload type (ECG, Geolocation,
  Battery, etc.) implements this protocol.

  ## Implementing the Protocol

  For each payload struct, implement all three functions:

      defimpl Sensocto.Protocols.AttributePayload, for: Sensocto.Payloads.ECGPayload do
        def validate(%ECGPayload{values: v}) when is_list(v), do: {:ok, @for}
        def validate(_), do: {:error, :invalid_ecg_payload}

        def display_value(%{values: values}), do: "\#{length(values)} samples"

        def render_hints(_) do
          %{
            component: "ECGVisualization",
            chart_type: :waveform,
            color: "#ffc107"
          }
        end
      end

  ## Usage in LiveView Components

  The `render_hints/1` function is particularly useful for dynamically
  selecting the appropriate visualization component:

      def render(assigns) do
        hints = AttributePayload.render_hints(assigns.payload)
        component = hints.component

        live_component(component, payload: assigns.payload)
      end
  """

  @doc """
  Validates the payload structure and values.

  Returns `{:ok, payload}` if valid, `{:error, reason}` otherwise.
  """
  @spec validate(t) :: {:ok, t} | {:error, term()}
  def validate(payload)

  @doc """
  Returns a human-readable display value for the payload.

  This is used in UI elements where a simple text representation
  is needed (e.g., tooltips, summary views).
  """
  @spec display_value(t) :: String.t()
  def display_value(payload)

  @doc """
  Returns rendering hints for UI components.

  The returned map should include at minimum:
  - `:component` - The name of the visualization component to use
  - `:chart_type` - The type of chart/visualization (:waveform, :map, :gauge, etc.)

  Optional fields:
  - `:color` - Default color for the visualization
  - `:unit` - Unit of measurement to display
  - `:range` - Valid range for values `{min, max}`
  """
  @spec render_hints(t) :: map()
  def render_hints(payload)
end

# Fallback implementation for plain maps
defimpl Sensocto.Protocols.AttributePayload, for: Map do
  def validate(payload), do: {:ok, payload}

  def display_value(payload) do
    case payload do
      %{value: v} when is_number(v) -> "#{v}"
      %{"value" => v} when is_number(v) -> "#{v}"
      _ -> inspect(payload, limit: 50)
    end
  end

  def render_hints(_payload) do
    %{
      component: "SparklineWasm",
      chart_type: :sparkline
    }
  end
end
