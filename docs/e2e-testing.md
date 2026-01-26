# End-to-End Testing Guide

This document covers the E2E testing setup for Sensocto's collaborative demo components (Whiteboard, Media Player, 3D Object Viewer).

## Overview

E2E tests use [Wallaby](https://github.com/elixir-wallaby/wallaby) with ChromeDriver to automate browser interactions. These tests verify that the collaborative features work correctly across devices and multiple users.

## Test Files

| File | Description | Test Count |
|------|-------------|------------|
| `test/sensocto_web/features/whiteboard_feature_test.exs` | Whiteboard drawing, tools, collaboration | ~20 |
| `test/sensocto_web/features/media_player_feature_test.exs` | YouTube sync, playlist, controls | ~18 |
| `test/sensocto_web/features/object3d_player_feature_test.exs` | 3D viewer, camera sync, gestures | ~22 |
| `test/sensocto_web/features/collab_demo_feature_test.exs` | Cross-component, multi-user, compatibility | ~22 |

## Running Tests

### Unit Tests Only (Default)

E2E tests are **excluded by default** because they require ChromeDriver and take longer to run:

```bash
mix test
```

### Include E2E Tests

```bash
mix test --include e2e
```

### E2E Tests Only

```bash
mix test test/sensocto_web/features/ --include e2e
```

### Specific Component

```bash
mix test test/sensocto_web/features/whiteboard_feature_test.exs --include e2e
```

### By Tag

```bash
# Multi-user tests only
mix test --include multi_user

# Touch-specific tests
mix test --include touch

# Slow tests (>5 seconds)
mix test --include slow
```

## Prerequisites

### 1. ChromeDriver

ChromeDriver must be installed and match your Chrome version:

```bash
# Check Chrome version
/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome --version

# Install/update ChromeDriver (macOS)
brew install chromedriver
# or
brew upgrade chromedriver
```

**Important:** Chrome and ChromeDriver must have matching major.minor.build versions.

### 2. Configuration

The test config (`config/test.exs`) includes:

```elixir
config :wallaby,
  driver: Wallaby.Chrome,
  base_url: "http://localhost:4002",
  screenshot_on_failure: true,
  screenshot_dir: "tmp/wallaby_screenshots",
  chromedriver: [
    headless: System.get_env("CI") == "true"
  ],
  max_wait_time: 10_000
```

## Test Tags

| Tag | Description |
|-----|-------------|
| `@tag :e2e` | All E2E tests (excluded by default) |
| `@tag :multi_user` | Tests with multiple browser sessions |
| `@tag :slow` | Tests taking > 5 seconds |
| `@tag :touch` | Touch event specific tests |
| `@tag :mobile` | Mobile viewport tests |

## Execution Time

Approximate test durations:

| Test Suite | Time |
|------------|------|
| Unit tests only | ~20-25 seconds |
| E2E tests only | ~2-3 minutes |
| All tests | ~3-4 minutes |

Multi-user tests (`@tag :multi_user`) are slower as they spawn additional browser sessions.

## Helper Functions

The `SensoctoWeb.FeatureCase.Helpers` module provides:

### Navigation
- `visit_lobby/1` - Navigate to lobby and wait for LiveView
- `sign_in_as_guest/1` - Sign in as guest user

### Component Waits
- `wait_for_whiteboard/1`
- `wait_for_media_player/1`
- `wait_for_object3d_player/1`

### Control Actions
- `take_whiteboard_control/1`, `release_whiteboard_control/1`
- `take_media_control/1`, `release_media_control/1`
- `take_object3d_control/1`, `release_object3d_control/1`

### Event Simulation
- `simulate_touch_tap/2` - Simulate touch tap
- `simulate_touch_drag/6` - Simulate touch drag gesture
- `simulate_mouse_drag/6` - Simulate mouse drag

### Viewport
- `set_mobile_viewport/1` - iPhone 12/13 (390x844)
- `set_tablet_viewport/1` - iPad (768x1024)
- `set_desktop_viewport/1` - Desktop (1920x1080)

## CI/CD Integration

For CI environments, set `CI=true` to run Chrome in headless mode:

```bash
CI=true mix test --include e2e
```

Failed tests automatically save screenshots to `tmp/wallaby_screenshots/`.

## Writing New E2E Tests

```elixir
defmodule SensoctoWeb.Features.MyFeatureTest do
  use SensoctoWeb.FeatureCase
  import Wallaby.Query

  @moduletag :e2e

  describe "my feature" do
    @tag :e2e
    test "does something", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_whiteboard()
      |> click(css("[phx-click='some_action']"))
      |> assert_has(css(".expected-element", visible: true))
    end

    @tag :e2e
    @tag :multi_user
    test "syncs between users", %{session: session1} do
      session1
      |> visit_lobby()
      |> click(css("[phx-click='take_control']"))

      {:ok, session2} = Wallaby.start_session()

      session2
      |> visit_lobby()
      |> assert_has(css("[phx-click='request_control']"))

      Wallaby.end_session(session2)
    end
  end
end
```

## Troubleshooting

### ChromeDriver Version Mismatch

```
warning: Looks like you're trying to run Wallaby with a mismatched version of Chrome
```

Solution: Update ChromeDriver to match Chrome version.

### NoBaseUrlError

```
Wallaby.NoBaseUrlError: You called visit with /lobby, but did not set a base_url
```

Solution: Ensure `config/test.exs` has `base_url: "http://localhost:4002"`.

### Element Not Found

Increase wait time or add explicit waits:

```elixir
|> then(fn session ->
  Process.sleep(500)
  session
end)
```

### Tests Hanging

Check if ChromeDriver process is running and not stale:

```bash
pkill -f chromedriver
```

## Device Compatibility Matrix

The E2E tests verify functionality across:

| Device Type | Input Method | Viewport |
|-------------|--------------|----------|
| Desktop | Mouse | 1920x1080 |
| Tablet | Touch + Mouse | 768x1024 |
| Mobile | Touch | 390x844 |

Tests check for:
- WebGL availability (3D viewer)
- Touch API support
- ResizeObserver (responsive canvas)
- CSS touch-action: none (drawing canvas)
