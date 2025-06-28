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

  @doc "Get list of all repositories from user config or default"
  def all_repositories do
    load_user_repositories() || @default_repositories
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

  @doc "Load repositories from user configuration files"
  def load_user_repositories do
    user_config_paths()
    |> Enum.find_value(&load_repositories_from_file/1)
  end

  @doc "Get default repositories list"
  def default_repositories, do: @default_repositories

  @doc "Get user configuration file paths in priority order"
  def user_config_paths do
    home_dir = System.get_env("HOME") || "."

    [
      # XDG config directory
      Path.join([
        System.get_env("XDG_CONFIG_HOME") || Path.join(home_dir, ".config"),
        "ecosystem-manager",
        "repositories.txt"
      ]),

      # Home directory dotfile
      Path.join(home_dir, ".ecosystem-manager-repositories"),

      # Legacy location in home directory
      Path.join(home_dir, ".ecosystem-repositories.txt"),

      # Current directory (for project-specific overrides)
      Path.join(File.cwd!(), ".ecosystem-repositories")
    ]
  end

  @doc "Load repositories from a specific file"
  def load_repositories_from_file(file_path) do
    if File.exists?(file_path) do
      case File.read(file_path) do
        {:ok, content} ->
          parse_repositories_file(content)

        {:error, reason} ->
          require Logger
          Logger.warning("Failed to read repository config: #{file_path} - #{reason}")
          nil
      end
    else
      nil
    end
  end

  @doc "Parse repositories file content"
  def parse_repositories_file(content) do
    content
    |> String.split(["\n", "\r\n"], trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(fn line ->
      String.starts_with?(line, "#") or String.trim(line) == ""
    end)
    |> case do
      [] -> nil
      repos -> repos
    end
  end

  @doc "Create user configuration directory if needed"
  def ensure_user_config_dir do
    config_dir =
      Path.join([
        System.get_env("XDG_CONFIG_HOME") || Path.join(System.get_env("HOME") || ".", ".config"),
        "ecosystem-manager"
      ])

    case File.mkdir_p(config_dir) do
      :ok -> config_dir
      # Return path even if mkdir fails
      {:error, _reason} -> config_dir
    end
  end

  @doc "Create example user configuration file"
  def create_example_config do
    config_dir = ensure_user_config_dir()
    example_file = Path.join(config_dir, "repositories.example.txt")

    example_content = """
    # EcosystemManager Repository Configuration
    # 
    # List one repository directory name per line
    # Lines starting with # are comments
    # Empty lines are ignored
    #
    # Special directory "." refers to the current ecosystem root

    # Core infrastructure
    .
    texlive-ja-textlint
    latex-environment
    aldc

    # Document templates
    sotsuron-template
    latex-template
    sotsuron-report-template
    wr-template
    ise-report-template

    # Tools and actions
    latex-release-action
    thesis-management-tools
    thesis-student-registry

    # AI reviewers
    ai-academic-paper-reviewer
    ai-reviewer

    # Add your custom repositories here:
    # my-custom-template
    # additional-tools
    """

    case File.write(example_file, example_content) do
      :ok ->
        {:ok, example_file}

      {:error, reason} ->
        {:error, reason}
    end
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
