# Exclude E2E tests by default (they require ChromeDriver and take longer)
# Run E2E tests explicitly with: mix test --include e2e
ExUnit.start(exclude: [:e2e])

Ecto.Adapters.SQL.Sandbox.mode(Sensocto.Repo, :manual)

# Start Wallaby for E2E tests (only when E2E tests are included)
{:ok, _} = Application.ensure_all_started(:wallaby)
