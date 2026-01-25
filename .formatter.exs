[
  import_deps: [
    :ash_admin,
    :ash_authentication,
    :ecto,
    :ecto_sql,
    :phoenix,
    :ash,
    :ash_postgres,
    :open_api_spex
  ],
  subdirectories: ["priv/*/migrations"],
  plugins: [Spark.Formatter, Phoenix.LiveView.HTMLFormatter],
  inputs: [
    ".claude.exs",
    "*.{heex,ex,exs}",
    "{config,lib,test}/**/*.{heex,ex,exs}",
    "priv/*/seeds.exs"
  ]
]
