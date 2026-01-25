# Modal Accessibility Implementation

## Overview

This document describes the accessibility improvements and comprehensive testing implemented for modal dialogs in the Sensocto application. The implementation follows WCAG 2.1 AA guidelines and ensures modals are fully accessible to keyboard users and screen reader users.

## Implementation Location

- **Component**: `/Users/adrianibanez/Documents/projects/2024_sensor-platform/sensocto/lib/sensocto_web/components/core_components.ex`
- **Tests**:
  - `/Users/adrianibanez/Documents/projects/2024_sensor-platform/sensocto/test/sensocto_web/components/core_components_test.exs`
  - `/Users/adrianibanez/Documents/projects/2024_sensor-platform/sensocto/test/sensocto_web/components/modal_accessibility_test.exs`

## Accessibility Features

### 1. ARIA Attributes

The modal component includes all required ARIA attributes for proper screen reader support:

```elixir
<div
  role="dialog"
  aria-modal="true"
  aria-labelledby={"#{@id}-title"}
  aria-describedby={"#{@id}-description"}
>
  <!-- Modal content -->
</div>
```

**ARIA Roles & Properties:**
- `role="dialog"`: Identifies the element as a dialog
- `aria-modal="true"`: Indicates that the modal is modal and requires user interaction
- `aria-labelledby`: Associates the modal with its title heading
- `aria-describedby`: Associates the modal with its description
- `aria-label="close"`: Provides an accessible label for the close button
- `aria-hidden="true"`: Hides the background overlay from screen readers

### 2. Keyboard Navigation

The modal supports full keyboard navigation:

- **Escape key**: Closes the modal
  ```elixir
  phx-window-keydown={JS.exec("data-cancel", to: "##{@id}")}
  phx-key="escape"
  ```

- **Tab/Shift+Tab**: Cycles focus through interactive elements within the modal (handled by focus_wrap)

- **Click away**: Closes modal when clicking outside
  ```elixir
  phx-click-away={JS.exec("data-cancel", to: "##{@id}")}
  ```

### 3. Focus Management

The modal uses Phoenix LiveView's `focus_wrap` component to implement a focus trap:

```elixir
<.focus_wrap
  id={"#{@id}-container"}
  phx-window-keydown={JS.exec("data-cancel", to: "##{@id}")}
  phx-key="escape"
  phx-click-away={JS.exec("data-cancel", to: "##{@id}")}
  class="..."
>
  <!-- Modal content -->
</.focus_wrap>
```

**Focus Management Features:**
- **Focus trap**: Keeps focus within the modal when open
- **Initial focus**: Automatically focuses the first interactive element when opened via `JS.focus_first`
- **Focus restoration**: Returns focus to the triggering element when closed via `JS.pop_focus`

### 4. Semantic HTML Structure

The modal follows proper semantic structure:

```elixir
<div id="modal-id" role="dialog" aria-modal="true">
  <div id="modal-id-bg" aria-hidden="true"><!-- Background overlay --></div>
  <div aria-labelledby="modal-id-title" aria-describedby="modal-id-description">
    <.focus_wrap>
      <button aria-label="close"><!-- Close button --></button>
      <div id="modal-id-content">
        <h2 id="modal-id-title">Title</h2>
        <p id="modal-id-description">Description</p>
        <!-- Interactive content -->
      </div>
    </.focus_wrap>
  </div>
</div>
```

### 5. Screen Reader Compatibility

The implementation ensures compatibility with major screen readers (NVDA, JAWS, VoiceOver):

- Background overlay is hidden from screen readers via `aria-hidden="true"`
- Modal title and description are properly associated
- Close button has an accessible label
- All form elements have proper labels

## Usage Guidelines

### Basic Modal with Accessibility

```elixir
<.modal id="confirm-modal">
  <.header>
    <h2 id="confirm-modal-title">Confirm Action</h2>
    <:subtitle>
      <p id="confirm-modal-description">
        Are you sure you want to proceed with this action?
      </p>
    </:subtitle>
  </.header>
  <div class="mt-4">
    <button type="button" phx-click="confirm">Confirm</button>
    <button type="button" phx-click="cancel">Cancel</button>
  </div>
</.modal>
```

### Required Elements for Accessibility

1. **Title Heading**: Must have id="{modal-id}-title"
   ```elixir
   <h2 id="confirm-modal-title">Title Text</h2>
   ```

2. **Description**: Must have id="{modal-id}-description"
   ```elixir
   <p id="confirm-modal-description">Description text</p>
   ```

3. **Close Button**: Automatically included with accessible label

### Custom On-Cancel Behavior

```elixir
<.modal id="navigate-modal" on_cancel={JS.navigate(~p"/posts")}>
  <h2 id="navigate-modal-title">Navigation Modal</h2>
  <p id="navigate-modal-description">This modal will navigate on close.</p>
</.modal>
```

## Testing

### Test Coverage

The implementation includes comprehensive tests covering:

1. **ARIA Attributes** (10 tests)
   - Proper role and aria-modal attributes
   - aria-labelledby and aria-describedby associations
   - aria-hidden on background overlay
   - aria-label on close button

2. **Keyboard Navigation** (4 tests)
   - Modal opens on button click
   - ARIA attributes present when open
   - Close button has accessible label
   - Background overlay hidden from screen readers

3. **Focus Management** (3 tests)
   - focus_wrap component contains content
   - Content area has proper ID structure
   - Interactive elements remain accessible

4. **Semantic Structure** (3 tests)
   - Heading properly associated via aria-labelledby
   - Description properly associated via aria-describedby
   - Dialog role correctly applied

5. **Close Behaviors** (2 tests)
   - Cancel button triggers close event
   - Form submission triggers close event

6. **Content Types** (2 tests)
   - Form elements maintain accessibility
   - Buttons have proper type attributes

### Running Tests

```bash
# Run all component tests
mix test test/sensocto_web/components/

# Run only modal accessibility tests
mix test test/sensocto_web/components/modal_accessibility_test.exs

# Run only core component tests
mix test test/sensocto_web/components/core_components_test.exs
```

## WCAG 2.1 AA Compliance

The modal implementation complies with the following WCAG 2.1 AA criteria:

### Level A Criteria

- **1.3.1 Info and Relationships**: Semantic structure using proper ARIA roles and relationships
- **2.1.1 Keyboard**: All functionality accessible via keyboard
- **2.1.2 No Keyboard Trap**: Focus can be moved away using Escape key
- **2.4.3 Focus Order**: Logical focus order within modal
- **3.2.2 On Input**: No unexpected context changes
- **4.1.2 Name, Role, Value**: All components have accessible names and roles

### Level AA Criteria

- **1.4.3 Contrast**: Relies on application's color scheme (not modal-specific)
- **2.4.7 Focus Visible**: Browser default focus indicators (application can enhance)

### Additional Best Practices

- **ARIA Authoring Practices**: Follows WAI-ARIA dialog pattern
- **Focus restoration**: Returns focus to triggering element on close
- **Focus trap**: Prevents focus from leaving modal while open
- **Escape to close**: Standard keyboard interaction for dialogs

## Browser & Screen Reader Support

The modal has been designed to work with:

- **Browsers**: Chrome, Firefox, Safari, Edge (modern versions)
- **Screen Readers**:
  - NVDA (Windows)
  - JAWS (Windows)
  - VoiceOver (macOS/iOS)
  - TalkBack (Android)

## Maintenance Notes

### When Modifying the Modal Component

1. **Maintain ARIA Attributes**: Ensure all ARIA attributes remain in place
2. **Test Keyboard Navigation**: Verify Escape and Tab still work correctly
3. **Check Focus Management**: Ensure focus_wrap continues to trap focus
4. **Run Tests**: Execute all modal tests after changes
5. **Manual Testing**: Test with a screen reader when making significant changes

### Adding New Modal Variants

When creating specialized modal components:

1. Extend the base modal component, don't replace it
2. Ensure new variants maintain all accessibility features
3. Add specific tests for new functionality
4. Update this documentation with new patterns

## Common Accessibility Pitfalls to Avoid

1. **Missing Title/Description IDs**: Always include properly-ID'd title and description
2. **Nested Interactivity**: Avoid nested interactive elements (button inside button)
3. **Auto-focus Input**: Don't auto-focus inputs without user action
4. **Missing Labels**: Ensure all form inputs have associated labels
5. **Hiding Content**: Use CSS classes, not `display: none` for initial state
6. **JavaScript-only Close**: Always provide a close button, not just click-away

## Future Enhancements

Potential improvements for consideration:

1. **Animated Focus Indicators**: Enhanced visual focus indicators during transitions
2. **Size Variants**: Predefined modal sizes (small, medium, large, full-screen)
3. **Alert Dialogs**: Specialized variant for alerts with role="alertdialog"
4. **Confirmation Patterns**: Pre-built confirmation dialog with standard buttons
5. **Multi-step Modals**: Support for wizard-style multi-step dialogs

## References

- [WAI-ARIA Authoring Practices - Dialog Pattern](https://www.w3.org/WAI/ARIA/apg/patterns/dialog-modal/)
- [WCAG 2.1 Guidelines](https://www.w3.org/WAI/WCAG21/quickref/)
- [Phoenix LiveView Documentation](https://hexdocs.pm/phoenix_live_view/)
- [Phoenix.Component focus_wrap](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html#focus_wrap/1)

## Support

For questions or issues related to modal accessibility:

1. Check this documentation first
2. Review test files for usage examples
3. Consult the component source code with inline comments
4. Reference WAI-ARIA dialog pattern documentation
