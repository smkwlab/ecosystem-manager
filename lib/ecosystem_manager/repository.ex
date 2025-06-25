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
          issues: map() | nil,
          pull_requests: map() | nil,
          status: :ok | :error | :missing
        }

  @repositories [
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

  @doc "Get list of all repositories"
  def all_repositories, do: @repositories

  @doc "Create a new repository struct"
  def new(name, base_path) do
    %__MODULE__{
      name: name,
      path: if(name == ".", do: base_path, else: Path.join(base_path, name)),
      display_name: get_display_name(name),
      status: :ok
    }
  end

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

  @doc "Update repository with git information"
  def fetch_git_info(repo) do
    if exists?(repo) do
      %{
        repo
        | branch: get_branch(repo),
          changes: get_changes(repo),
          last_commit: get_last_commit(repo)
      }
    else
      %{repo | status: :missing, changes: :missing}
    end
  end

  # Private functions

  defp get_display_name("."), do: "latex-ecosystem"
  defp get_display_name(name), do: name
end
