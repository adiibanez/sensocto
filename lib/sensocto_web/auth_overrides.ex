# https://team-alembic.github.io/ash_authentication_phoenix/ui-overrides.html

defmodule SensoctoWeb.AuthOverrides do
  use AshAuthentication.Phoenix.Overrides

  # Override a property per component
  override AshAuthentication.Phoenix.Components.SignIn do
    # include any number of properties you want to override
    # set :image_url, "/images/rickroll.gif"
    set(:show_banner, false)
  end
end
