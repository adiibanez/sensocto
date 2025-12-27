defmodule Sensocto.Payloads.ECGPayload do
  @moduledoc """
  ECG signal payload with waveform data.

  ECG data consists of an array of voltage samples captured at a
  specific sampling rate. Typical sampling rates are 128, 256, or 512 Hz.

  ## Example

      iex> ECGPayload.from_map(%{"values" => [0.1, 0.2, 0.15], "sample_rate" => 512})
      {:ok, %ECGPayload{values: [0.1, 0.2, 0.15], sample_rate: 512}}
  """

  @type t :: %__MODULE__{
          values: [number()],
          sample_rate: pos_integer(),
          lead: String.t() | nil
        }

  @enforce_keys [:values]
  defstruct [:values, sample_rate: 512, lead: nil]

  @doc """
  Creates an ECGPayload from a map.

  ## Parameters
  - `params` - Map with "values" (required), "sample_rate" (optional), "lead" (optional)

  ## Examples

      iex> ECGPayload.from_map(%{"values" => [0.1, 0.2, 0.3]})
      {:ok, %ECGPayload{values: [0.1, 0.2, 0.3], sample_rate: 512}}

      iex> ECGPayload.from_map(%{"invalid" => "data"})
      {:error, :invalid_ecg_payload}
  """
  @spec from_map(map()) :: {:ok, t()} | {:error, :invalid_ecg_payload}
  def from_map(%{"values" => values} = params) when is_list(values) do
    if Enum.all?(values, &is_number/1) do
      {:ok,
       %__MODULE__{
         values: values,
         sample_rate: Map.get(params, "sample_rate", 512),
         lead: Map.get(params, "lead")
       }}
    else
      {:error, :invalid_ecg_payload}
    end
  end

  def from_map(%{values: values} = params) when is_list(values) do
    from_map(%{
      "values" => values,
      "sample_rate" => Map.get(params, :sample_rate, 512),
      "lead" => Map.get(params, :lead)
    })
  end

  def from_map(_), do: {:error, :invalid_ecg_payload}

  @doc """
  Returns the duration of the ECG sample in milliseconds.
  """
  @spec duration_ms(t()) :: float()
  def duration_ms(%__MODULE__{values: values, sample_rate: sr}) do
    length(values) / sr * 1000
  end

  defimpl Sensocto.Protocols.AttributePayload do
    def validate(%Sensocto.Payloads.ECGPayload{values: v, sample_rate: sr})
        when is_list(v) and sr > 0 do
      {:ok, @for}
    end

    def validate(_), do: {:error, :invalid_ecg_payload}

    def display_value(%{values: values, sample_rate: sr}) do
      duration = length(values) / sr * 1000
      "#{length(values)} samples (#{Float.round(duration, 1)}ms)"
    end

    def render_hints(%{sample_rate: sr}) do
      %{
        component: "ECGVisualization",
        chart_type: :waveform,
        color: "#ffc107",
        sample_rate: sr
      }
    end
  end
end
