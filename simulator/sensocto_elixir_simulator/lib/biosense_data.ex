defmodule Sensocto.BiosenseData do
  alias NimbleCSV.RFC4180, as: CSV

  @moduledoc """
  BiosenseData
  """

  defp fetch_fake_sensor_data(config) do
    """
    1737604423651,0,51.0
    1737604424651,1.0,54.0
    1737604425651,1.0,58.0
    1737604426651,1.0,61.0
    1737604427651,1.0,65.0
    1737604428651,1.0,66.0
    1737604429651,1.0,66.0
    1737604430651,1.0,70.0
    1737604431651,1.0,72.0
    1737604432651,1.0,77.0
    1737604433651,1.0,83.0
    1737604434651,1.0,86.0
    1737604435651,1.0,88.0
    1737604436651,1.0,89.0
    1737604437651,1.0,90.0
    1737604438651,1.0,92.0
    1737604439651,1.0,90.0
    1737604440651,1.0,91.0
    1737604441651,1.0,96.0
    1737604442651,1.0,98.0
    1737604443651,1.0,101.0
    1737604444651,1.0,101.0
    1737604445651,1.0,102.0
    1737604446651,1.0,102.0
    1737604447651,1.0,101.0
    1737604448651,1.0,98.0
    1737604449651,1.0,97.0
    1737604450651,1.0,97.0
    1737604451651,1.0,97.0
    1737604452651,1.0,98.0
    """
  end

  def fetch_python_data(config) do
    System.cmd("python3", [
      "../sensocto-simulator.py",
      "--mode",
      "csv",
      "--sensor_id",
      "#{config[:sensor_id]}",
      "--sensor_type",
      "#{config[:sensor_type]}",
      "--duration",
      "#{config[:duration]}",
      "--sampling_rate",
      "#{config[:sampling_rate]}",
      "--heart_rate",
      "#{config[:heart_rate]}",
      "--respiratory_rate",
      "#{config[:respiratory_rate]}",
      "--scr_number",
      "#{config[:scr_number]}",
      "--burst_number",
      "#{config[:burst_number]}"
    ])
  end

  def fetch_sensor_data(config) do
    try do
      case config[:dummy_data] do
        true -> fetch_fake_sensor_data(config)
        _ -> fetch_python_data(config)
      end
      |> (fn
            {output, 0} ->
              output
              |> String.trim()
              |> CSV.parse_string()
              |> Enum.drop(1)
              |> Enum.map(fn item ->
                %{
                  timestamp: String.to_integer(Enum.at(item, 0)),
                  delay: String.to_float(Enum.at(item, 1)),
                  payload: String.to_float(Enum.at(item, 2))
                }
              end)
              |> (fn data ->
                    {:ok, data}
                  end).()

            {output, status} ->
              IO.puts("Error executing python script")
              IO.inspect(output)
              IO.inspect(status)
              :error
          end).()
    rescue
      e ->
        IO.puts("Error executing python script")
        IO.inspect(e)
        :error
    end
  end
end
