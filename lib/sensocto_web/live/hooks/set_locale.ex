defmodule SensoctoWeb.Live.Hooks.SetLocale do
  @moduledoc """
  LiveView hook that sets the Gettext locale from session.

  Priority order for determining locale:
  1. User preference (for authenticated users)
  2. Session value (set by Locale plug from cookie/header)
  3. Default locale (en)
  """
  import Phoenix.Component

  alias Sensocto.Accounts.UserPreferences

  @supported_locales ~w(en de gsw fr es pt_BR zh ja)

  def on_mount(:default, _params, session, socket) do
    locale = determine_locale(session, socket.assigns[:current_user])
    Gettext.put_locale(SensoctoWeb.Gettext, locale)

    {:cont, assign(socket, :locale, locale)}
  end

  defp determine_locale(session, user) do
    locale =
      get_user_locale_preference(user) ||
        get_session_locale(session) ||
        default_locale()

    if locale in @supported_locales, do: locale, else: default_locale()
  end

  defp get_user_locale_preference(nil), do: nil

  defp get_user_locale_preference(user) do
    case UserPreferences.get_ui_state(user.id, "locale") do
      {:ok, locale} when is_binary(locale) -> locale
      locale when is_binary(locale) -> locale
      _ -> nil
    end
  end

  defp get_session_locale(session) do
    session["locale"]
  end

  defp default_locale do
    Application.get_env(:sensocto, SensoctoWeb.Gettext, [])
    |> Keyword.get(:default_locale, "en")
  end
end
