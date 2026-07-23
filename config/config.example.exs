import Config

# EcosystemManager Configuration Example
# Copy this file to config.exs and modify as needed

# Logger configuration
config :logger, level: :info

config :logger, :console,
  level: :info,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# EcosystemManager configuration
config :ecosystem_manager,
  # Parallel processing settings
  # Number of concurrent repository processing tasks
  default_concurrency: 8,

  # Timeout settings (milliseconds)
  # GitHub API request timeout
  github_timeout: 15_000,
  # Git command timeout
  git_timeout: 5_000,

  # Output formatting
  # Options: :compact, :long
  default_format: :compact,

  # Cache settings for gh CLI results (issue/pr list), keyed per repository.
  # Enable result caching (bypass at runtime with --no-cache)
  enable_cache: false,
  # Cache time-to-live (5 minutes; milliseconds, converted to seconds)
  cache_ttl: 300_000,
  # Base directory for the GitHub result cache
  cache_dir: "~/.cache/ecosystem-manager",

  # Performance monitoring
  # Enable execution timing logs
  enable_timing: false,

  # GitHub API settings
  github_api_base_url: "https://api.github.com",
  # Include GitHub data by default
  default_include_github: true

# Environment-specific configurations
case config_env() do
  :dev ->
    config :ecosystem_manager,
      # Enable timing in development
      enable_timing: true,
      # Lower concurrency for development
      default_concurrency: 4

  :test ->
    config :ecosystem_manager,
      # Shorter timeout for tests
      github_timeout: 5_000,
      git_timeout: 2_000,
      default_concurrency: 2,
      enable_cache: false

  :prod ->
    config :ecosystem_manager,
      # Higher concurrency for production
      default_concurrency: 12,
      # Enable caching in production
      enable_cache: true,
      # 10 minute cache in production
      cache_ttl: 600_000
end
