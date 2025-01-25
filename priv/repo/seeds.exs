# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Sensocto.Repo.insert!(%Sensocto.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.
alias Sensocto.Sensors.Sensor

# sensor_id: "Movesense 11119191991",
#|> Ash.Changeset.change_attribute("name", "Test")
Sensor|> Ash.Changeset.for_create(:create, %{name: "Movesense 11119191991" }) |> Ash.create()
Sensor|> Ash.Changeset.for_create(:create, %{name: "Pressuresensor" }) |> Ash.create()
Sensor|> Ash.Changeset.for_create(:create, %{name: "Flexsense" }) |> Ash.create()