defmodule SensoctoWeb.FeatureCase do
  @moduledoc """
  This module defines the test case to be used by E2E feature tests
  that require browser automation via Wallaby.

  Such tests simulate real user interactions with the application,
  including JavaScript hooks, LiveView components, and real-time sync.

  ## Usage

      use SensoctoWeb.FeatureCase

  ## Tags

  - `@tag :e2e` - All feature tests are tagged with :e2e
  - `@tag :slow` - Tests that take longer than 5 seconds
  - `@tag :multi_user` - Tests involving multiple browser sessions

  Note: E2E tests are currently disabled. This module is a placeholder
  for future browser-based testing with Wallaby/ChromeDriver.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      use Wallaby.Feature

      import Wallaby.Query
      import SensoctoWeb.FeatureCase.Helpers

      @endpoint SensoctoWeb.Endpoint
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Sensocto.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(Sensocto.Repo, {:shared, self()})
    end

    # Configure Wallaby to use the sandbox
    metadata = Phoenix.Ecto.SQL.Sandbox.metadata_for(Sensocto.Repo, self())
    {:ok, session} = Wallaby.start_session(metadata: metadata)

    {:ok, session: session}
  end
end

defmodule SensoctoWeb.FeatureCase.Helpers do
  @moduledoc """
  Helper functions for E2E feature tests.
  """

  use Wallaby.DSL
  import Wallaby.Query

  @doc """
  Waits for a LiveView to be connected and ready.
  """
  def wait_for_liveview(session) do
    session
    |> assert_has(css("[data-phx-main]", visible: true))
  end

  @doc """
  Navigates to the lobby page and waits for it to load.
  """
  def visit_lobby(session) do
    session
    |> visit("/lobby")
    |> wait_for_liveview()
  end

  @doc """
  Waits for the media player component to be visible.
  """
  def wait_for_media_player(session) do
    session
    |> assert_has(css("[id*='media-player']", visible: true))
  end

  @doc """
  Waits for the 3D object player component to be visible.
  """
  def wait_for_object3d_player(session) do
    session
    |> assert_has(css("[id*='object3d-player']", visible: true))
  end

  @doc """
  Clicks the play button in the media player.
  """
  def click_play(session) do
    session
    |> click(css("[phx-click='play']"))
  end

  @doc """
  Clicks the pause button in the media player.
  """
  def click_pause(session) do
    session
    |> click(css("[phx-click='pause']"))
  end

  @doc """
  Clicks the next button in a player.
  """
  def click_next(session) do
    session
    |> click(css("[phx-click='next']"))
  end

  @doc """
  Clicks the previous button in a player.
  """
  def click_previous(session) do
    session
    |> click(css("[phx-click='previous']"))
  end

  @doc """
  Takes control of the media player.
  """
  def take_media_control(session) do
    session
    |> click(css("[phx-click='take_control']"))
  end

  @doc """
  Releases control of the media player.
  """
  def release_media_control(session) do
    session
    |> click(css("[phx-click='release_control']"))
  end

  @doc """
  Executes JavaScript in the browser and returns the result.
  """
  def execute_js(session, script) do
    execute_script(session, script)
  end
end
