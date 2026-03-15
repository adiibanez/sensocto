# https://team-alembic.github.io/ash_authentication_phoenix/ui-overrides.html

defmodule SensoctoWeb.AuthOverrides do
  use AshAuthentication.Phoenix.Overrides

  override AshAuthentication.Phoenix.Components.SignIn do
    set(:show_banner, false)
    set(:root_class, "w-full")
    set(:strategy_class, "w-full")
  end

  override AshAuthentication.Phoenix.Components.Password.Input do
    set(:label_class, "block text-sm font-medium text-gray-300 mb-1")
    set(:field_class, "mt-2 mb-2 text-white")
  end
end
