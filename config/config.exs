# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

# By default, the umbrella project as well as each child
# application will require this configuration file, ensuring
# they all use the same configuration. While one could
# configure all applications here, we prefer to delegate
# back to each application for organization purposes.
import_config "../apps/*/config/config.exs"

%{year: year, month: month, day: day} = DateTime.utc_now()
timestamp = "#{year}-#{month}-#{day}_"

config :aecore, :keys,
  password: "secret",
  dir: "/tmp/keys"

config :logger,
  compile_time_purge_level: :info,
  backends: [{LoggerFileBackend, :info},
             {LoggerFileBackend, :error}]

config :logger, :info,
  path: "apps/aecore/logs/#{timestamp}info.log",
  level: :info

config :logger, :error,
  path: "apps/aecore/logs/#{timestamp}error.log",
  level: :error
