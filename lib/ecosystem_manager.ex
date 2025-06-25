defmodule EcosystemManager do
  @moduledoc """
  LaTeX Thesis Environment Ecosystem Manager

  A high-performance Elixir implementation of the ecosystem manager
  that provides utilities for managing the multi-repository ecosystem
  with parallel processing and improved performance.
  """

  alias EcosystemManager.Status

  @doc """
  Get status of all repositories.

  ## Options

    * `:include_github` - Whether to fetch GitHub API data (default: true)
    * `:max_concurrency` - Maximum parallel operations (default: 8)
    * `:base_path` - Base path for repositories (default: current directory)

  ## Examples

      iex> repos = EcosystemManager.status(include_github: false)
      iex> is_list(repos)
      true
      iex> length(repos) > 0
      true
  """
  def status(opts \\ []) do
    base_path = Keyword.get(opts, :base_path, File.cwd!())
    Status.get_all_status(base_path, opts)
  end

  @doc """
  Get status of a specific repository.
  """
  def repository_status(repo_name, opts \\ []) do
    base_path = Keyword.get(opts, :base_path, File.cwd!())
    Status.get_repository_status(repo_name, base_path, opts)
  end

  @doc """
  Format repository status for display.
  """
  def format_status(repos, opts \\ []) do
    Status.format_status(repos, opts)
  end
end
