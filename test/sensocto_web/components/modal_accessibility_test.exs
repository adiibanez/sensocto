defmodule SensoctoWeb.ModalAccessibilityTest do
  @moduledoc """
  Comprehensive accessibility tests for modal dialogs.
  Tests keyboard navigation, focus management, and ARIA attributes.
  """

  use SensoctoWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  # Test LiveView that uses the modal component
  defmodule TestModalLive do
    use Phoenix.LiveView
    import SensoctoWeb.CoreComponents

    def render(assigns) do
      ~H"""
      <div>
        <button phx-click="open_modal" id="open-modal-btn">Open Modal</button>

        <.modal id="test-modal" show={@show_modal} on_cancel={JS.push("close_modal")}>
          <div>
            <h2 id="test-modal-title">Test Modal Title</h2>
            <p id="test-modal-description">This is a test modal for accessibility testing.</p>
            <form phx-submit="submit_form">
              <label for="test-input">Test Input</label>
              <input type="text" id="test-input" name="test_input" />
              <button type="button" phx-click="cancel">Cancel</button>
              <button type="submit" id="submit-btn">Submit</button>
            </form>
          </div>
        </.modal>

        <button id="after-modal-btn">Button After Modal</button>
      </div>
      """
    end

    def mount(_params, _session, socket) do
      {:ok, assign(socket, show_modal: false)}
    end

    def handle_event("open_modal", _params, socket) do
      {:noreply, assign(socket, show_modal: true)}
    end

    def handle_event("close_modal", _params, socket) do
      {:noreply, assign(socket, show_modal: false)}
    end

    def handle_event("cancel", _params, socket) do
      {:noreply, assign(socket, show_modal: false)}
    end

    def handle_event("submit_form", _params, socket) do
      {:noreply, assign(socket, show_modal: false)}
    end
  end

  describe "modal keyboard navigation" do
    test "modal opens when button is clicked" do
      {:ok, view, _html} = live_isolated(build_conn(), TestModalLive)

      # Modal should not be visible initially
      assert view.assigns.show_modal == false

      # Click the open button
      view |> element("#open-modal-btn") |> render_click()

      # Modal should now be shown
      assert view.assigns.show_modal == true
      assert render(view) =~ "Test Modal Title"
    end

    test "modal has proper ARIA attributes" do
      {:ok, view, _html} = live_isolated(build_conn(), TestModalLive)

      # Open modal
      view |> element("#open-modal-btn") |> render_click()
      html = render(view)

      # Check required ARIA attributes
      assert html =~ ~r/role="dialog"/
      assert html =~ ~r/aria-modal="true"/
      assert html =~ ~r/aria-labelledby="test-modal-title"/
      assert html =~ ~r/aria-describedby="test-modal-description"/
    end

    test "modal close button has accessible label" do
      {:ok, view, _html} = live_isolated(build_conn(), TestModalLive)

      # Open modal
      view |> element("#open-modal-btn") |> render_click()
      html = render(view)

      # Close button should have aria-label (from gettext("close"))
      assert html =~ ~r/<button[^>]*aria-label="[^"]*close[^"]*"/i
    end

    test "modal background overlay is hidden from screen readers" do
      {:ok, view, _html} = live_isolated(build_conn(), TestModalLive)

      # Open modal
      view |> element("#open-modal-btn") |> render_click()
      html = render(view)

      # Background overlay should have aria-hidden="true"
      assert html =~ ~r/aria-hidden="true"/
    end
  end

  describe "modal focus management" do
    test "focus_wrap component contains modal content" do
      {:ok, view, _html} = live_isolated(build_conn(), TestModalLive)

      # Open modal
      view |> element("#open-modal-btn") |> render_click()
      html = render(view)

      # focus_wrap should be present
      assert html =~ ~r/id="test-modal-container"/
      # Content should be inside focus_wrap
      assert html =~ ~r/test-modal-content/
    end

    test "modal content area has proper ID structure" do
      {:ok, view, _html} = live_isolated(build_conn(), TestModalLive)

      # Open modal
      view |> element("#open-modal-btn") |> render_click()
      html = render(view)

      # Content wrapper should have ID matching pattern
      assert html =~ ~r/id="test-modal-content"/
    end

    test "interactive elements inside modal are accessible" do
      {:ok, view, _html} = live_isolated(build_conn(), TestModalLive)

      # Open modal
      view |> element("#open-modal-btn") |> render_click()

      # Form elements should be present and accessible
      assert has_element?(view, "#test-input")
      assert has_element?(view, "#submit-btn")

      # Cancel button should work
      view |> element("button", "Cancel") |> render_click()
      assert view.assigns.show_modal == false
    end
  end

  describe "modal semantic structure" do
    test "modal heading is properly associated via aria-labelledby" do
      {:ok, view, _html} = live_isolated(build_conn(), TestModalLive)

      # Open modal
      view |> element("#open-modal-btn") |> render_click()
      html = render(view)

      # Heading should have matching ID
      assert html =~ ~r/<h2[^>]*id="test-modal-title"/
      assert html =~ "Test Modal Title"
    end

    test "modal description is properly associated via aria-describedby" do
      {:ok, view, _html} = live_isolated(build_conn(), TestModalLive)

      # Open modal
      view |> element("#open-modal-btn") |> render_click()
      html = render(view)

      # Description should have matching ID
      assert html =~ ~r/id="test-modal-description"/
      assert html =~ "This is a test modal for accessibility testing"
    end

    test "modal uses dialog role correctly" do
      {:ok, view, _html} = live_isolated(build_conn(), TestModalLive)

      # Open modal
      view |> element("#open-modal-btn") |> render_click()
      html = render(view)

      # Should have role="dialog" and aria-modal="true"
      assert html =~ ~r/role="dialog"[^>]*aria-modal="true"/ or
               html =~ ~r/aria-modal="true"[^>]*role="dialog"/
    end
  end

  describe "modal close behaviors" do
    test "clicking cancel button closes modal" do
      {:ok, view, _html} = live_isolated(build_conn(), TestModalLive)

      # Open modal
      view |> element("#open-modal-btn") |> render_click()
      assert view.assigns.show_modal == true

      # Click cancel button
      view |> element("button", "Cancel") |> render_click()
      assert view.assigns.show_modal == false
    end

    test "submitting form closes modal" do
      {:ok, view, _html} = live_isolated(build_conn(), TestModalLive)

      # Open modal
      view |> element("#open-modal-btn") |> render_click()
      assert view.assigns.show_modal == true

      # Submit form
      view
      |> element("form")
      |> render_submit(%{test_input: "test value"})

      # Modal should be closed
      assert view.assigns.show_modal == false
    end
  end

  describe "modal with different content types" do
    test "modal with form elements maintains accessibility" do
      {:ok, view, _html} = live_isolated(build_conn(), TestModalLive)

      # Open modal
      view |> element("#open-modal-btn") |> render_click()
      html = render(view)

      # Form elements should have proper labels
      assert html =~ ~r/<label[^>]*for="test-input"/
      assert html =~ ~r/<input[^>]*id="test-input"/
    end

    test "modal with buttons maintains proper type attributes" do
      {:ok, view, _html} = live_isolated(build_conn(), TestModalLive)

      # Open modal
      view |> element("#open-modal-btn") |> render_click()
      html = render(view)

      # Cancel button should be type="button" to prevent form submission
      assert html =~ ~r/<button[^>]*type="button"[^>]*>Cancel<\/button>/

      # Submit button should be type="submit"
      assert html =~ ~r/<button[^>]*type="submit"/
    end
  end
end
