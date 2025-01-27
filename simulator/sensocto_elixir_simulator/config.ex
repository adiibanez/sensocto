import Config

config :logger,
  level: :info,
  backends: [:console],
  compile_time_purge_level: :debug
