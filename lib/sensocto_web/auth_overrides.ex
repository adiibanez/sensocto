# https://team-alembic.github.io/ash_authentication_phoenix/ui-overrides.html

defmodule SensoctoWeb.AuthOverrides do
  use AshAuthentication.Phoenix.Overrides

  override AshAuthentication.Phoenix.Components.SignIn do
    set(:show_banner, false)
    # Center the content, remove the large padding that shifts content right
    set(:root_class, "w-full")
    set(:strategy_class, "w-full")
  end
end
