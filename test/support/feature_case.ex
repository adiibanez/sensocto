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

  ## Device Compatibility

  These helpers support testing across:
  - Desktop browsers (mouse events)
  - Mobile browsers (touch events)
  - Tablets (hybrid touch/mouse)

  ## Usage

  All helpers return the session for chaining:

      session
      |> visit_lobby()
      |> wait_for_whiteboard()
      |> take_whiteboard_control()
  """

  use Wallaby.DSL
  import Wallaby.Query

  # ==========================================================================
  # Navigation Helpers
  # ==========================================================================

  @doc """
  Waits for a LiveView to be connected and ready.
  """
  def wait_for_liveview(session) do
    session
    |> assert_has(css("[data-phx-main]", visible: true))
  end

  @doc """
  Navigates to the lobby page and waits for it to load.
  Automatically signs in as guest first since /lobby requires authentication.
  """
  def visit_lobby(session) do
    session
    |> sign_in_as_guest()
    |> visit("/lobby")
    |> wait_for_liveview()
  end

  @doc """
  Signs in as a guest user for testing.
  """
  def sign_in_as_guest(session) do
    session
    |> visit("/sign-in")
    |> click(css("[phx-click='join_as_guest']"))
    |> wait_for_liveview()
  end

  # ==========================================================================
  # Collab Tab Switching Helpers
  # ==========================================================================

  @doc """
  Switches to the whiteboard tab in the lobby.
  The collab demos are tabbed - only one is visible at a time.
  """
  def switch_to_whiteboard_tab(session) do
    session
    |> click(css("button", text: "Whiteboard"))
    |> then(fn s ->
      Process.sleep(300)
      s
    end)
  end

  @doc """
  Switches to the media player tab in the lobby.
  """
  def switch_to_media_tab(session) do
    session
    |> click(css("button", text: "Media"))
    |> then(fn s ->
      Process.sleep(300)
      s
    end)
  end

  @doc """
  Switches to the 3D object player tab in the lobby.
  """
  def switch_to_object3d_tab(session) do
    session
    |> click(css("button", text: "3D Object"))
    |> then(fn s ->
      Process.sleep(300)
      s
    end)
  end

  # ==========================================================================
  # Component Wait Helpers
  # ==========================================================================

  @doc """
  Waits for the whiteboard component to be visible and ready.
  Note: Must switch to whiteboard tab first in lobby view.
  """
  def wait_for_whiteboard(session) do
    session
    |> assert_has(css("#whiteboard-lobby", visible: true))
  end

  @doc """
  Waits for the media player component to be visible.
  Note: Must switch to media tab first in lobby view.
  """
  def wait_for_media_player(session) do
    session
    |> assert_has(css("[id*='media-player']", visible: true))
  end

  @doc """
  Waits for the 3D object player component to be visible.
  Note: Must switch to 3D object tab first in lobby view.
  """
  def wait_for_object3d_player(session) do
    session
    |> assert_has(css("[id*='object3d-player']", visible: true))
  end

  # ==========================================================================
  # Media Player Helpers
  # ==========================================================================

  @doc """
  Clicks the play button in the media player.
  """
  def click_play(session) do
    session
    |> click(css("[id*='media-player'] [phx-click='play']"))
  end

  @doc """
  Clicks the pause button in the media player.
  """
  def click_pause(session) do
    session
    |> click(css("[id*='media-player'] [phx-click='pause']"))
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
    |> click(css("[id*='media-player'] [phx-click='take_control']"))
  end

  @doc """
  Releases control of the media player.
  """
  def release_media_control(session) do
    session
    |> click(css("[id*='media-player'] [phx-click='release_control']"))
  end

  # ==========================================================================
  # Whiteboard Helpers
  # ==========================================================================

  @doc """
  Takes control of the whiteboard.
  """
  def take_whiteboard_control(session) do
    session
    |> click(css("[id*='whiteboard-'] [phx-click='take_control']"))
  end

  @doc """
  Releases control of the whiteboard.
  """
  def release_whiteboard_control(session) do
    session
    |> click(css("[id*='whiteboard-'] [phx-click='release_control']"))
  end

  @doc """
  Selects a tool on the whiteboard.
  """
  def select_whiteboard_tool(session, tool) when tool in ["pen", "eraser", "line", "rect"] do
    session
    |> click(css("[phx-click='set_tool'][phx-value-tool='#{tool}']"))
  end

  # ==========================================================================
  # 3D Object Player Helpers
  # ==========================================================================

  @doc """
  Takes control of the 3D object player.
  """
  def take_object3d_control(session) do
    session
    |> click(css("[id*='object3d-player'] [phx-click='take_control']"))
  end

  @doc """
  Releases control of the 3D object player.
  """
  def release_object3d_control(session) do
    session
    |> click(css("[id*='object3d-player'] [phx-click='release_control']"))
  end

  # ==========================================================================
  # JavaScript Execution Helpers
  # ==========================================================================

  @doc """
  Executes JavaScript in the browser and returns the result.
  """
  def execute_js(session, script) do
    execute_script(session, script)
  end

  # ==========================================================================
  # Touch Event Simulation Helpers
  # ==========================================================================

  @doc """
  Simulates a touch tap on an element.
  """
  def simulate_touch_tap(session, selector) do
    execute_script(session, """
      const el = document.querySelector('#{selector}');
      if (!el) return;

      const rect = el.getBoundingClientRect();
      const touch = new Touch({
        identifier: 1,
        target: el,
        clientX: rect.left + rect.width / 2,
        clientY: rect.top + rect.height / 2
      });

      el.dispatchEvent(new TouchEvent('touchstart', {
        bubbles: true, cancelable: true,
        touches: [touch], targetTouches: [touch], changedTouches: [touch]
      }));

      el.dispatchEvent(new TouchEvent('touchend', {
        bubbles: true, cancelable: true,
        touches: [], targetTouches: [], changedTouches: [touch]
      }));

      el.click();
    """)

    session
  end

  @doc """
  Simulates a touch drag from one point to another on an element.
  """
  def simulate_touch_drag(session, selector, from_x, from_y, to_x, to_y) do
    execute_script(session, """
      const el = document.querySelector('#{selector}');
      if (!el) return;

      const rect = el.getBoundingClientRect();
      const startX = rect.left + (rect.width * #{from_x});
      const startY = rect.top + (rect.height * #{from_y});
      const endX = rect.left + (rect.width * #{to_x});
      const endY = rect.top + (rect.height * #{to_y});

      const touch1 = new Touch({
        identifier: 1, target: el,
        clientX: startX, clientY: startY
      });

      const touch2 = new Touch({
        identifier: 1, target: el,
        clientX: endX, clientY: endY
      });

      el.dispatchEvent(new TouchEvent('touchstart', {
        bubbles: true, cancelable: true,
        touches: [touch1], targetTouches: [touch1], changedTouches: [touch1]
      }));

      setTimeout(() => {
        el.dispatchEvent(new TouchEvent('touchmove', {
          bubbles: true, cancelable: true,
          touches: [touch2], targetTouches: [touch2], changedTouches: [touch2]
        }));

        setTimeout(() => {
          el.dispatchEvent(new TouchEvent('touchend', {
            bubbles: true, cancelable: true,
            touches: [], targetTouches: [], changedTouches: [touch2]
          }));
        }, 50);
      }, 50);
    """)

    Process.sleep(200)
    session
  end

  # ==========================================================================
  # Mouse Event Simulation Helpers
  # ==========================================================================

  @doc """
  Simulates a mouse drag from one point to another on an element.
  """
  def simulate_mouse_drag(session, selector, from_x, from_y, to_x, to_y) do
    execute_script(session, """
      const el = document.querySelector('#{selector}');
      if (!el) return;

      const rect = el.getBoundingClientRect();
      const startX = rect.left + (rect.width * #{from_x});
      const startY = rect.top + (rect.height * #{from_y});
      const endX = rect.left + (rect.width * #{to_x});
      const endY = rect.top + (rect.height * #{to_y});

      el.dispatchEvent(new MouseEvent('mousedown', {
        bubbles: true, cancelable: true,
        clientX: startX, clientY: startY, button: 0
      }));

      setTimeout(() => {
        el.dispatchEvent(new MouseEvent('mousemove', {
          bubbles: true, cancelable: true,
          clientX: endX, clientY: endY, button: 0
        }));

        setTimeout(() => {
          el.dispatchEvent(new MouseEvent('mouseup', {
            bubbles: true, cancelable: true,
            clientX: endX, clientY: endY, button: 0
          }));
        }, 50);
      }, 50);
    """)

    Process.sleep(200)
    session
  end

  # ==========================================================================
  # Viewport Helpers
  # ==========================================================================

  @doc """
  Sets a mobile viewport size (iPhone 12/13).
  """
  def set_mobile_viewport(session) do
    resize_window(session, 390, 844)
  end

  @doc """
  Sets a tablet viewport size (iPad).
  """
  def set_tablet_viewport(session) do
    resize_window(session, 768, 1024)
  end

  @doc """
  Sets a desktop viewport size.
  """
  def set_desktop_viewport(session) do
    resize_window(session, 1920, 1080)
  end
end
