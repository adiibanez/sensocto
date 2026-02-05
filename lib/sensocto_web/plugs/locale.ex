defmodule SensoctoWeb.Plugs.Locale do
  @moduledoc """
  Plug for handling locale/language selection.

  Determines the user's preferred locale from (in order of priority):
  1. Query parameter `?locale=xx`
  2. Session value
  3. Cookie value
  4. Accept-Language header
  5. Default locale (en)

  Sets the Gettext locale and stores the preference in session and cookie.
  """
  import Plug.Conn

  @supported_locales ~w(en de gsw fr es pt_BR zh ja)
  @cookie_key "locale"
  @cookie_max_age 365 * 24 * 60 * 60

  def init(opts), do: opts

  def call(conn, _opts) do
    locale =
      get_locale_from_params(conn) ||
        get_locale_from_session(conn) ||
        get_locale_from_cookie(conn) ||
        get_locale_from_accept_language(conn) ||
        default_locale()

    locale = if locale in @supported_locales, do: locale, else: default_locale()

    Gettext.put_locale(SensoctoWeb.Gettext, locale)

    conn
    |> put_session(:locale, locale)
    |> put_resp_cookie(@cookie_key, locale, max_age: @cookie_max_age)
  end

  defp get_locale_from_params(conn) do
    conn.params["locale"]
  end

  defp get_locale_from_session(conn) do
    get_session(conn, :locale)
  end

  defp get_locale_from_cookie(conn) do
    conn.cookies[@cookie_key]
  end

  defp get_locale_from_accept_language(conn) do
    case get_req_header(conn, "accept-language") do
      [accept_language | _] -> parse_accept_language(accept_language)
      _ -> nil
    end
  end

  defp parse_accept_language(header) do
    header
    |> String.split(",")
    |> Enum.map(&parse_language_tag/1)
    |> Enum.sort_by(fn {_lang, quality} -> quality end, :desc)
    |> Enum.find_value(fn {lang, _quality} ->
      normalized = normalize_locale(lang)
      if normalized in @supported_locales, do: normalized
    end)
  end

  defp parse_language_tag(tag) do
    case String.split(String.trim(tag), ";") do
      [lang] ->
        {String.trim(lang), 1.0}

      [lang, quality_str] ->
        quality =
          case Regex.run(~r/q=([0-9.]+)/, quality_str) do
            [_, q] -> String.to_float(q)
            _ -> 1.0
          end

        {String.trim(lang), quality}
    end
  end

  defp normalize_locale(lang) do
    lang = String.downcase(lang)

    cond do
      lang in @supported_locales ->
        lang

      String.starts_with?(lang, "de-ch") or String.starts_with?(lang, "gsw") ->
        "gsw"

      String.starts_with?(lang, "de") ->
        "de"

      String.starts_with?(lang, "fr") ->
        "fr"

      String.starts_with?(lang, "es") ->
        "es"

      String.starts_with?(lang, "pt-br") or String.starts_with?(lang, "pt_br") ->
        "pt_BR"

      String.starts_with?(lang, "pt") ->
        "pt_BR"

      String.starts_with?(lang, "zh") ->
        "zh"

      String.starts_with?(lang, "ja") ->
        "ja"

      String.starts_with?(lang, "en") ->
        "en"

      true ->
        nil
    end
  end

  defp default_locale do
    Application.get_env(:sensocto, SensoctoWeb.Gettext, [])
    |> Keyword.get(:default_locale, "en")
  end
end
