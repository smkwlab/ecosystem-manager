import Config

# Test environment configuration
config :ecosystem_manager,
  env: :test,
  # Disable GitHub API calls in tests by default
  default_include_github: false
