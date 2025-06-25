import Config

# Configure Logger to only show info level and above by default
config :logger, level: :info

# Configure console backend to be more quiet
config :logger, :console,
  level: :info,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]
