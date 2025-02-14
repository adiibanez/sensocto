import Config

config :logger,
  logger: :console,
  level: :info,
  # default_level: :info,
  backends: [{FlexLogger, :logger_name}],
  format: "DEV $message\n",
  compile_time_purge_matching: [
    # [level_lower_than: :error]
  ]

# config :logger,
#   compile_time_purge_matching: [
#     [application: :foo],
#     [module: Bar, function: "foo/3", level_lower_than: :error]
# ]

config :logger, :logger_name,
  logger: :console,
  # this is the loggers default level
  # override default levels
  level_config: [
    # [module: Sensocto.SensorSimulatorGenServer, level: :debug]
    [module: Sensocto.AttributeGenServer, level: :info],
    [module: Sensocto.ConnectorGenServer, level: :debug]
    #    [module: Phoenix.Logger, level: :info]
  ]

# backend specific configuration

# Do not include metadata nor timestamps in development logs
# config :logger, :console, format: "[$level] $message\n"
