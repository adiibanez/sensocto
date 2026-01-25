defmodule SensoctoWeb.CoreComponentsTest do
  use SensoctoWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Phoenix.Component
  import SensoctoWeb.CoreComponents

  describe "modal/1 accessibility" do
    test "renders with proper ARIA attributes" do
      assigns = %{id: "test-modal", show: false, on_cancel: %Phoenix.LiveView.JS{}}

      html =
        rendered_to_string(~H"""
        <.modal id={@id} show={@show} on_cancel={@on_cancel}>
          <p id="test-modal-content">Modal content</p>
        </.modal>
        """)

      # Check dialog role and aria-modal
      assert html =~ ~r/role="dialog"/
      assert html =~ ~r/aria-modal="true"/

      # Check aria-labelledby and aria-describedby
      assert html =~ ~r/aria-labelledby="test-modal-title"/
      assert html =~ ~r/aria-describedby="test-modal-description"/

      # Check for close button with aria-label
      assert html =~ ~r/aria-label=".*close.*"/i
    end

    test "modal container is initially hidden" do
      assigns = %{id: "hidden-modal", show: false, on_cancel: %Phoenix.LiveView.JS{}}

      html =
        rendered_to_string(~H"""
        <.modal id={@id} show={@show} on_cancel={@on_cancel}>
          <p>Content</p>
        </.modal>
        """)

      # Modal container should have hidden class
      assert html =~ ~r/class="[^"]*hidden[^"]*"/
    end

    test "focus_wrap component is present for focus management" do
      assigns = %{id: "focus-modal", show: false, on_cancel: %Phoenix.LiveView.JS{}}

      html =
        rendered_to_string(~H"""
        <.modal id={@id} show={@show} on_cancel={@on_cancel}>
          <p>Content</p>
        </.modal>
        """)

      # Check that focus_wrap is used
      assert html =~ ~r/id="focus-modal-container"/
    end

    test "escape key handler is configured" do
      assigns = %{id: "esc-modal", show: false, on_cancel: %Phoenix.LiveView.JS{}}

      html =
        rendered_to_string(~H"""
        <.modal id={@id} show={@show} on_cancel={@on_cancel}>
          <p>Content</p>
        </.modal>
        """)

      # Check for escape key handling
      assert html =~ ~r/phx-window-keydown/
      assert html =~ ~r/phx-key="escape"/
    end

    test "click-away handler is configured" do
      assigns = %{id: "click-modal", show: false, on_cancel: %Phoenix.LiveView.JS{}}

      html =
        rendered_to_string(~H"""
        <.modal id={@id} show={@show} on_cancel={@on_cancel}>
          <p>Content</p>
        </.modal>
        """)

      # Check for click-away handling
      assert html =~ ~r/phx-click-away/
    end

    test "close button includes proper icon and accessibility label" do
      assigns = %{id: "btn-modal", show: false, on_cancel: %Phoenix.LiveView.JS{}}

      html =
        rendered_to_string(~H"""
        <.modal id={@id} show={@show} on_cancel={@on_cancel}>
          <p>Content</p>
        </.modal>
        """)

      # Check close button structure
      assert html =~ ~r/<button[^>]*phx-click[^>]*>/
      assert html =~ ~r/type="button"/
      assert html =~ ~r/hero-x-mark-solid/
    end

    test "modal content area has proper ID for content" do
      assigns = %{id: "content-modal", show: false, on_cancel: %Phoenix.LiveView.JS{}}

      html =
        rendered_to_string(~H"""
        <.modal id={@id} show={@show} on_cancel={@on_cancel}>
          <p>Modal body</p>
        </.modal>
        """)

      # Content area should be identifiable
      assert html =~ ~r/id="content-modal-content"/
    end

    test "background overlay has aria-hidden" do
      assigns = %{id: "bg-modal", show: false, on_cancel: %Phoenix.LiveView.JS{}}

      html =
        rendered_to_string(~H"""
        <.modal id={@id} show={@show} on_cancel={@on_cancel}>
          <p>Content</p>
        </.modal>
        """)

      # Background should be hidden from screen readers
      assert html =~ ~r/aria-hidden="true"/
    end
  end

  describe "modal/1 with show=true" do
    test "phx-mounted attribute is set when show is true" do
      assigns = %{id: "shown-modal", show: true, on_cancel: %Phoenix.LiveView.JS{}}

      html =
        rendered_to_string(~H"""
        <.modal id={@id} show={@show} on_cancel={@on_cancel}>
          <p>Visible content</p>
        </.modal>
        """)

      # When show is true, phx-mounted should trigger show_modal
      assert html =~ ~r/phx-mounted/
    end
  end

  describe "modal integration with headers" do
    test "modal content can include proper heading structure" do
      assigns = %{id: "heading-modal", show: false, on_cancel: %Phoenix.LiveView.JS{}}

      html =
        rendered_to_string(~H"""
        <.modal id={@id} show={@show} on_cancel={@on_cancel}>
          <.header>
            <h2 id="heading-modal-title">Confirmation</h2>
            <:subtitle>
              <p id="heading-modal-description">Are you sure you want to proceed?</p>
            </:subtitle>
          </.header>
        </.modal>
        """)

      # Verify heading structure
      assert html =~ ~r/<h2[^>]*id="heading-modal-title"/
      assert html =~ "Confirmation"
      assert html =~ "Are you sure you want to proceed?"
    end
  end
end
