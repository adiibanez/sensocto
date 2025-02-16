defmodule SensoctoWeb.Live.LvnEntryLive.SwiftUI do
  use SensoctoNative, [:render_component, format: :swiftui]
  require Logger

  def time_ago_from_unix(timestamp) do
    timestamp |> dbg()

    diff = Timex.diff(Timex.now(), Timex.from_unix(timestamp, :millisecond), :millisecond)

    case diff > 1000 do
      true ->
        timestamp
        |> Timex.from_unix(:milliseconds)
        |> Timex.format!("{relative}", :relative)

      _ ->
        "#{abs(diff)}ms ago"
    end
  end
end
