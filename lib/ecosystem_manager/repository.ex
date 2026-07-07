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

  @doc """
  Get the list of ecosystem repositories with precedence:
  explicit config (`:repositories`) > auto-discovery under `base_path`.

  The explicit `:repositories` pin is a single global list, so it is only
  honored when at most one workspace is configured. With multiple workspaces
  each resolves its own list via discovery under its own `base_path`.
  """
  def all_repositories(base_path) do
    if single_workspace?() do
      get_configured_repositories() || discover(base_path)
    else
      discover(base_path)
    end
  end

  defp single_workspace? do
    length(EcosystemManager.Workspace.list()) <= 1
  end

  @doc """
  Discover ecosystem repositories under `base_path`.

  Scans the immediate subdirectories of `base_path` for Git repositories and
  returns their names, always including `"."` for the workspace root itself.

  When the ecosystem organization can be determined (an explicit
  `:ecosystem_org` config value, otherwise the `origin` owner of `base_path`
  itself), only subdirectories whose `origin` remote belongs to that
  organization are included; this keeps unrelated personal clones out of the
  list. Directories whose name ends in `-test` are treated as test fixtures
  and excluded.
  """
  def discover(base_path) do
    org = ecosystem_org(base_path)

    discovered =
      case File.ls(base_path) do
        {:ok, entries} -> entries
        {:error, _} -> []
      end
      |> Enum.filter(&ecosystem_member?(&1, Path.join(base_path, &1), org))
      |> Enum.sort()

    ["." | discovered]
  end

  defp ecosystem_member?(name, path, org) do
    git_repo?(path) and not test_fixture?(name) and org_match?(path, org)
  end

  defp git_repo?(path) do
    File.dir?(path) and File.dir?(Path.join(path, ".git"))
  end

  defp test_fixture?(name), do: String.ends_with?(name, "-test")

  defp org_match?(_path, nil), do: true
  defp org_match?(path, org), do: origin_owner(path) == org

  @doc """
  Determine the ecosystem organization for `base_path`.

  Uses the `:ecosystem_org` config value when set, otherwise falls back to the
  `origin` remote owner of `base_path` itself. Returns nil when neither is
  available, in which case discovery applies no organization filter.
  """
  def ecosystem_org(base_path) do
    EcosystemManager.Config.ecosystem_org() || origin_owner(base_path)
  end

  @doc "Return the owner of a repository's `origin` remote, or nil."
  def origin_owner(path) do
    case System.cmd("git", ["-C", path, "remote", "get-url", "origin"], stderr_to_stdout: true) do
      {url, 0} -> parse_owner(String.trim(url))
      _ -> nil
    end
  rescue
    # System.cmd raises when git is unavailable or the path is invalid
    _ -> nil
  end

  @doc """
  Parse the owner (organization or user) from a Git remote URL.

  Handles the common GitHub URL shapes and returns nil for anything that does
  not contain an `owner/repo` pair.

  ## Examples

      iex> EcosystemManager.Repository.parse_owner("git@github.com:smkwlab/aldc.git")
      "smkwlab"

      iex> EcosystemManager.Repository.parse_owner("https://github.com/smkwlab/aldc.git")
      "smkwlab"

      iex> EcosystemManager.Repository.parse_owner("ssh://git@github.com/smkwlab/aldc.git")
      "smkwlab"

      iex> EcosystemManager.Repository.parse_owner("not-a-url")
      nil
  """
  def parse_owner(url) when is_binary(url) do
    segments =
      url
      |> String.replace(~r/\.git\z/, "")
      |> String.trim_trailing("/")
      |> String.split(~r{[/:]}, trim: true)

    case Enum.take(segments, -2) do
      [owner, _repo] -> if owner =~ ~r/\./, do: nil, else: owner
      _ -> nil
    end
  end

  def parse_owner(_), do: nil

  @doc "Create a new repository struct"
  def new(name, base_path) do
    %__MODULE__{
      name: name,
      path: if(name == ".", do: base_path, else: Path.join(base_path, name)),
      display_name: display_name(name, base_path),
      status: :ok
    }
  end

  @doc "Get configured repositories from application config (nil when unset)"
  def get_configured_repositories do
    EcosystemManager.Config.repositories()
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

  # The workspace root ("." ) is shown by its directory name, so each workspace
  # displays its own name rather than a hardcoded one. `base_path` is always an
  # absolute path from the caller, so `Path.basename/1` is deterministic (no
  # `Path.expand/1`, which would depend on the current working directory).
  defp display_name(".", base_path), do: Path.basename(base_path)
  defp display_name(name, _base_path), do: name
end
