defmodule EcosystemManager.Repository do
  @moduledoc """
  Repository information and operations.
  """

  defstruct [
    :name,
    :path,
    :display_name,
    :branch,
    :changes,
    :last_commit,
    :last_commit_timestamp,
    :issues,
    :pull_requests,
    :status
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          path: String.t(),
          display_name: String.t(),
          branch: String.t() | nil,
          changes: integer() | :missing,
          last_commit: String.t() | nil,
          last_commit_timestamp: integer() | nil,
          issues: map() | nil,
          pull_requests: map() | nil,
          status: :ok | :error | :missing
        }

  @default_repositories [
    ".",
    "texlive-ja-textlint",
    "latex-environment",
    "aldc",
    "sotsuron-template",
    "latex-template",
    "sotsuron-report-template",
    "wr-template",
    "ise-report-template",
    "latex-release-action",
    "thesis-management-tools",
    "thesis-student-registry",
    "ai-academic-paper-reviewer",
    "ai-reviewer"
  ]

  @doc "Get list of all repositories with precedence: config > defaults"
  def all_repositories do
    get_configured_repositories() || @default_repositories
  end

  @doc "Create a new repository struct"
  def new(name, base_path) do
    %__MODULE__{
      name: name,
      path: if(name == ".", do: base_path, else: Path.join(base_path, name)),
      display_name: get_display_name(name),
      status: :ok
    }
  end

  @doc "Get configured repositories from application config"
  def get_configured_repositories do
    EcosystemManager.Config.repositories()
  end

  @doc "Get default repositories list"
  def default_repositories, do: @default_repositories

  @doc "Check if repository exists"
  def exists?(%__MODULE__{path: path}) do
    File.dir?(path) and File.dir?(Path.join(path, ".git"))
  end

  @doc "Get current git branch"
  def get_branch(%__MODULE__{path: path}) do
    case System.cmd("git", ["branch", "--show-current"], cd: path, stderr_to_stdout: true) do
      {branch, 0} -> String.trim(branch)
      _ -> nil
    end
  end

  @doc "Get number of uncommitted changes"
  def get_changes(%__MODULE__{path: path}) do
    case System.cmd("git", ["status", "--porcelain"], cd: path, stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> length()

      _ ->
        :missing
    end
  end

  @doc "Get last commit info"
  def get_last_commit(%__MODULE__{path: path}) do
    case System.cmd("git", ["log", "-1", "--format=%h %cr"], cd: path, stderr_to_stdout: true) do
      {commit, 0} -> String.trim(commit)
      _ -> nil
    end
  end

  @doc "Get last commit timestamp for sorting"
  def get_last_commit_timestamp(%__MODULE__{path: path}) do
    case System.cmd("git", ["log", "-1", "--format=%ct"], cd: path, stderr_to_stdout: true) do
      {timestamp, 0} ->
        case String.trim(timestamp) |> Integer.parse() do
          {ts, _} -> ts
          _ -> 0
        end

      _ ->
        0
    end
  end

  @doc "Update repository with git information"
  def fetch_git_info(repo) do
    if exists?(repo) do
      %{
        repo
        | branch: get_branch(repo),
          changes: get_changes(repo),
          last_commit: get_last_commit(repo),
          last_commit_timestamp: get_last_commit_timestamp(repo)
      }
    else
      %{repo | status: :missing, changes: :missing}
    end
  end

  # Private functions

  defp get_display_name("."), do: "latex-ecosystem"
  defp get_display_name(name), do: name
end
