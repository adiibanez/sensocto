# Sensocto

To start your Phoenix server:

  * Run `mix setup` to install and setup dependencies
  * Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

  * Official website: https://www.phoenixframework.org/
  * Guides: https://hexdocs.pm/phoenix/overview.html
  * Docs: https://hexdocs.pm/phoenix
  * Forum: https://elixirforum.com/c/phoenix-forum
  * Source: https://github.com/phoenixframework/phoenix



https://blog.miguelcoba.com/creating-a-phoenix-16-application-with-asdf

https://apollin.com/how-to-install-elixir-on-ubuntu-22-using-asdf/



asdf global erlang 26.2.4
asdf global elixir 1.16.2-otp-26



config/dev.ex
username: System.get_env("PGUSER", "postgres"),
password: System.get_env("PGPASSWORD", "postgres"),
database: System.get_env("PGDATABASE", "myapp_dev"),
hostname: System.get_env("PGHOST", "localhost"),
port: String.to_integer(System.get_env("PGPORT", "5432")),