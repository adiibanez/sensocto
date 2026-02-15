defmodule SensoctoWeb.Live.Hooks.SetLocale do
  @moduledoc """
  LiveView hook that sets the Gettext locale from session.

  Priority order for determining locale:
  1. User preference (for authenticated users)
  2. Session value (set by Locale plug from cookie/header)
  3. Default locale (en)

  Also provides:
  - `@locales` assign for language picker UI in layouts
  - `@current_uri_path` tracking for locale-preserving redirects
  - Global `change_locale` event handler (saves to DB + redirects)
  """
  import Phoenix.Component
  import Phoenix.LiveView

  alias Sensocto.Accounts.UserPreferences

  @supported_locales ~w(en de gsw fr es pt_BR zh ja)

  @locale_options [
    {"EN", "en"},
    {"DE", "de"},
    {"CH", "gsw"},
    {"FR", "fr"},
    {"ES", "es"},
    {"PT", "pt_BR"},
    {"中文", "zh"},
    {"日本", "ja"}
  ]

  def on_mount(:default, _params, session, socket) do
    locale = determine_locale(session, socket.assigns[:current_user])
    Gettext.put_locale(SensoctoWeb.Gettext, locale)

    socket =
      socket
      |> assign(:locale, locale)
      |> assign(:locale_label, locale_label(locale))
      |> assign(:locales, @locale_options)
      |> assign(:current_uri_path, "/")
      |> attach_hook(:locale_uri, :handle_params, &track_uri/3)
      |> attach_hook(:locale_event, :handle_event, &handle_locale_event/3)

    {:cont, socket}
  end

  defp track_uri(_params, uri, socket) do
    path = URI.parse(uri).path || "/"
    {:cont, assign(socket, :current_uri_path, path)}
  end

  defp handle_locale_event("change_locale", %{"locale" => locale}, socket) do
    if locale in @supported_locales do
      user = socket.assigns[:current_user]
      if user, do: UserPreferences.set_ui_state(user.id, "locale", locale)
      path = socket.assigns[:current_uri_path] || "/"
      {:halt, redirect(socket, to: "#{path}?locale=#{locale}")}
    else
      {:cont, socket}
    end
  end

  defp handle_locale_event(_event, _params, socket), do: {:cont, socket}

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

  defp locale_label(code) do
    Enum.find_value(@locale_options, String.upcase(code), fn
      {label, ^code} -> label
      _ -> nil
    end)
  end
end
