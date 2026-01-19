ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Sensocto.Repo, :manual)

# Start Wallaby for E2E tests
{:ok, _} = Application.ensure_all_started(:wallaby)
