defmodule Sensocto.Payloads.GeolocationPayload do
  @moduledoc """
  Geolocation payload with GPS coordinates.

  Contains latitude, longitude, and optional accuracy/altitude data.
  Coordinates are in WGS84 format (standard GPS).

  ## Example

      iex> GeolocationPayload.from_map(%{
      ...>   "latitude" => 37.7749,
      ...>   "longitude" => -122.4194,
      ...>   "accuracy" => 10.5
      ...> })
      {:ok, %GeolocationPayload{latitude: 37.7749, longitude: -122.4194, accuracy: 10.5}}
  """

  @type t :: %__MODULE__{
          latitude: float(),
          longitude: float(),
          accuracy: float() | nil,
          altitude: float() | nil,
          speed: float() | nil,
          heading: float() | nil
        }

  @enforce_keys [:latitude, :longitude]
  defstruct [:latitude, :longitude, :accuracy, :altitude, :speed, :heading]

  @doc """
  Creates a GeolocationPayload from a map.

  ## Required fields
  - "latitude" - Latitude in degrees (-90 to 90)
  - "longitude" - Longitude in degrees (-180 to 180)

  ## Optional fields
  - "accuracy" - Accuracy in meters
  - "altitude" - Altitude in meters
  - "speed" - Speed in m/s
  - "heading" - Heading in degrees (0-360)
  """
  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(%{"latitude" => lat, "longitude" => lon} = params)
      when is_number(lat) and is_number(lon) do
    if valid_coordinates?(lat, lon) do
      {:ok,
       %__MODULE__{
         latitude: lat / 1,
         longitude: lon / 1,
         accuracy: get_float(params, "accuracy"),
         altitude: get_float(params, "altitude"),
         speed: get_float(params, "speed"),
         heading: get_float(params, "heading")
       }}
    else
      {:error, :invalid_coordinates}
    end
  end

  def from_map(%{latitude: lat, longitude: lon} = params) do
    from_map(%{
      "latitude" => lat,
      "longitude" => lon,
      "accuracy" => Map.get(params, :accuracy),
      "altitude" => Map.get(params, :altitude),
      "speed" => Map.get(params, :speed),
      "heading" => Map.get(params, :heading)
    })
  end

  def from_map(_), do: {:error, :invalid_geolocation_payload}

  @doc """
  Calculates the distance in meters between two geolocation payloads.
  Uses the Haversine formula.
  """
  @spec distance_meters(t(), t()) :: float()
  def distance_meters(%__MODULE__{} = a, %__MODULE__{} = b) do
    # Earth's radius in meters
    r = 6_371_000

    lat1 = a.latitude * :math.pi() / 180
    lat2 = b.latitude * :math.pi() / 180
    delta_lat = (b.latitude - a.latitude) * :math.pi() / 180
    delta_lon = (b.longitude - a.longitude) * :math.pi() / 180

    a_val =
      :math.sin(delta_lat / 2) * :math.sin(delta_lat / 2) +
        :math.cos(lat1) * :math.cos(lat2) *
          :math.sin(delta_lon / 2) * :math.sin(delta_lon / 2)

    c = 2 * :math.atan2(:math.sqrt(a_val), :math.sqrt(1 - a_val))

    r * c
  end

  defp valid_coordinates?(lat, lon) do
    lat >= -90 and lat <= 90 and lon >= -180 and lon <= 180
  end

  defp get_float(map, key) do
    case Map.get(map, key) do
      n when is_number(n) -> n / 1
      _ -> nil
    end
  end

  defimpl Sensocto.Protocols.AttributePayload do
    def validate(%Sensocto.Payloads.GeolocationPayload{latitude: lat, longitude: lon})
        when lat >= -90 and lat <= 90 and lon >= -180 and lon <= 180 do
      {:ok, @for}
    end

    def validate(_), do: {:error, :invalid_coordinates}

    def display_value(%{latitude: lat, longitude: lon, accuracy: acc}) do
      lat_str = Float.round(lat, 6) |> to_string()
      lon_str = Float.round(lon, 6) |> to_string()
      acc_str = if acc, do: " (±#{round(acc)}m)", else: ""
      "#{lat_str}, #{lon_str}#{acc_str}"
    end

    def render_hints(%{latitude: lat, longitude: lon, accuracy: acc}) do
      %{
        component: "Map",
        chart_type: :map,
        zoom: zoom_for_accuracy(acc),
        center: %{lat: lat, lng: lon}
      }
    end

    defp zoom_for_accuracy(nil), do: 15
    defp zoom_for_accuracy(acc) when acc < 10, do: 18
    defp zoom_for_accuracy(acc) when acc < 50, do: 16
    defp zoom_for_accuracy(acc) when acc < 200, do: 14
    defp zoom_for_accuracy(_), do: 12
  end
end
