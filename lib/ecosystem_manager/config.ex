defmodule EcosystemManager.Config do
  @moduledoc """
  Configuration management for EcosystemManager.

  Provides centralized access to application configuration with fallback defaults.
  """

  @doc """
  Get default concurrency for parallel processing.
  """
  def default_concurrency do
    Application.get_env(:ecosystem_manager, :default_concurrency, 8)
  end

  @doc """
  Get GitHub API timeout in milliseconds.
  """
  def github_timeout do
    Application.get_env(:ecosystem_manager, :github_timeout, 15_000)
  end

  @doc """
  Get Git command timeout in milliseconds.
  """
  def git_timeout do
    Application.get_env(:ecosystem_manager, :git_timeout, 5_000)
  end

  @doc """
  Get default output format.
  """
  def default_format do
    Application.get_env(:ecosystem_manager, :default_format, :compact)
  end

  @doc """
  Check if cache is enabled.
  """
  def cache_enabled? do
    Application.get_env(:ecosystem_manager, :enable_cache, false)
  end

  @doc """
  Get cache TTL in milliseconds.
  """
  def cache_ttl do
    Application.get_env(:ecosystem_manager, :cache_ttl, 300_000)
  end

  @doc """
  Check if timing is enabled.
  """
  def timing_enabled? do
    Application.get_env(:ecosystem_manager, :enable_timing, false)
  end

  @doc """
  Get GitHub API base URL.
  """
  def github_api_base_url do
    Application.get_env(:ecosystem_manager, :github_api_base_url, "https://api.github.com")
  end

  @doc """
  Get default include GitHub setting.
  """
  def default_include_github do
    Application.get_env(:ecosystem_manager, :default_include_github, true)
  end

  @doc """
  Get workspace path configuration.
  Returns nil if not configured.
  """
  def workspace_path do
    Application.get_env(:ecosystem_manager, :workspace_path)
  end

  @doc """
  Get repositories configuration.
  Returns nil if not configured.
  """
  def repositories do
    Application.get_env(:ecosystem_manager, :repositories)
  end

  @doc """
  Get all configuration as a keyword list.
  """
  def all do
    [
      default_concurrency: default_concurrency(),
      github_timeout: github_timeout(),
      git_timeout: git_timeout(),
      default_format: default_format(),
      cache_enabled: cache_enabled?(),
      cache_ttl: cache_ttl(),
      timing_enabled: timing_enabled?(),
      github_api_base_url: github_api_base_url(),
      default_include_github: default_include_github(),
      workspace_path: workspace_path(),
      repositories: repositories()
    ]
  end
end
