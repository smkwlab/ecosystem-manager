import Config

# Configure Logger to only show info level and above by default
config :logger, level: :info

# Configure console backend to be more quiet
config :logger, :console,
  level: :info,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# EcosystemManager configuration
config :ecosystem_manager,
  # Default concurrency for parallel repository processing
  default_concurrency: 8,

  # Timeout settings (milliseconds)
  github_timeout: 15_000,
  git_timeout: 5_000,

  # Default format for output
  default_format: :compact,

  # Cache settings (for future implementation)
  enable_cache: false,
  # 5 minutes
  cache_ttl: 300_000,

  # Performance monitoring
  enable_timing: false,

  # GitHub API settings
  github_api_base_url: "https://api.github.com",
  default_include_github: true,

  # Workspace path (can be overridden by user config)
  workspace_path: nil,

  # Repository list (can be overridden by user config)
  repositories: nil
