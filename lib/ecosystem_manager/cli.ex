defmodule EcosystemManager.CLI do
  @moduledoc """
  Command Line Interface for Ecosystem Manager.
  """

  alias EcosystemManager.Config
  alias EcosystemManager.Repository
  alias EcosystemManager.Status
  alias EcosystemManager.UserConfig

  def main(args) do
    args
    |> parse_args()
    |> execute()
  end

  def parse_args(args) do
    {opts, command_args, _} =
      OptionParser.parse(args,
        switches: [
          help: :boolean,
          long: :boolean,
          fast: :boolean,
          urgent_issues: :boolean,
          with_prs: :boolean,
          needs_review: :boolean,
          max_concurrency: :integer
        ],
        aliases: [
          h: :help,
          l: :long,
          f: :fast
        ]
      )

    command =
      case command_args do
        [] -> "status"
        [cmd | _] -> cmd
      end

    %{
      command: command,
      opts: opts,
      base_path: get_base_path()
    }
  end

  defp execute(%{opts: opts} = config) do
    if opts[:help] do
      show_help()
    else
      continue_execute(config)
    end
  end

  defp continue_execute(%{command: "status"} = config) do
    execute_status(config)
  end

  defp continue_execute(%{command: "help"}) do
    show_help()
  end

  defp continue_execute(%{command: "config"}) do
    show_config()
  end

  defp continue_execute(%{command: "repos"}) do
    show_repositories()
  end

  defp continue_execute(%{command: "init-config"}) do
    init_config()
  end

  defp continue_execute(%{command: "workspace"}) do
    show_workspace_path()
  end

  defp continue_execute(%{command: unknown}) do
    IO.puts("Unknown command: #{unknown}")
    IO.puts("Run 'ecosystem-manager help' for usage information.")

    # Use exit instead of System.halt for testability
    exit({:shutdown, 1})
  end

  defp execute_status(%{opts: opts, base_path: base_path}) do
    IO.puts("Repository Status Overview")
    IO.puts("")

    # Configure options
    status_opts = [
      include_github: !opts[:fast],
      max_concurrency: opts[:max_concurrency] || 8
    ]

    format_opts = [
      format: if(opts[:long], do: :long, else: :compact),
      filters: build_filters(opts)
    ]

    # Show timing information
    start_time = System.monotonic_time(:millisecond)

    # Get status
    repos = Status.get_all_status(base_path, status_opts)

    end_time = System.monotonic_time(:millisecond)
    elapsed = end_time - start_time

    # Format and display
    output = Status.format_status(repos, format_opts)
    IO.puts(output)

    # Show performance info
    if opts[:fast] do
      IO.puts("\n(Fast mode - GitHub API calls skipped)")
    end

    IO.puts("\nCompleted in #{elapsed}ms")
  end

  def build_filters(opts) do
    []
    |> maybe_add_filter(opts[:urgent_issues], {:urgent_issues_only, true})
    |> maybe_add_filter(opts[:with_prs], {:with_prs_only, true})
    |> maybe_add_filter(opts[:needs_review], {:needs_review_only, true})
  end

  defp maybe_add_filter(filters, true, filter), do: [filter | filters]
  defp maybe_add_filter(filters, _, _), do: filters

  defp get_base_path do
    # First check if workspace_path is configured
    case Config.workspace_path() do
      nil ->
        # If not configured, fall back to finding ecosystem root
        current_dir = System.get_env("PWD") || File.cwd!()
        find_ecosystem_root(current_dir) || current_dir

      path ->
        # Expand home directory if needed
        expanded_path = Path.expand(path)

        if File.dir?(expanded_path) do
          expanded_path
        else
          IO.puts("Warning: Configured workspace_path does not exist: #{expanded_path}")
          IO.puts("Falling back to current directory detection.")
          current_dir = System.get_env("PWD") || File.cwd!()
          find_ecosystem_root(current_dir) || current_dir
        end
    end
  end

  def find_ecosystem_root(dir) do
    ecosystem_marker = Path.join(dir, "ecosystem-manager.sh")

    cond do
      File.exists?(ecosystem_marker) -> dir
      dir == "/" -> nil
      true -> find_ecosystem_root(Path.dirname(dir))
    end
  end

  defp show_help do
    IO.puts("""
    LaTeX Thesis Environment Ecosystem Manager (Elixir Edition)

    USAGE:
        ecosystem-manager [COMMAND] [OPTIONS]

    COMMANDS:
        status          Show status of all repositories (default)
        config          Show current configuration
        repos           Show repository configuration and sources
        workspace       Show workspace path (for use with cd command)
        init-config     Create example user configuration files
        help            Show this help message

    STATUS OPTIONS:
        -l, --long             Show detailed status with full information
        -f, --fast             Fast mode - skip GitHub API calls
        --urgent-issues        Show only repositories with urgent issues
        --with-prs            Show only repositories with open PRs
        --needs-review        Show only repositories with PRs needing review
        --max-concurrency N   Maximum parallel operations (default: 8)

    EXAMPLES:
        ecosystem-manager                    # Show compact status
        ecosystem-manager status --long     # Show detailed status
        ecosystem-manager status --fast     # Quick status without GitHub API
        ecosystem-manager status --urgent-issues  # Filter urgent issues
        cd $(ecosystem-manager workspace)   # Change to workspace directory

    PERFORMANCE:
        This Elixir version uses parallel processing to significantly improve
        performance compared to the original Bash script.
        
        Expected performance:
        - Fast mode:     ~1-2 seconds 
        - Full mode:     ~2-4 seconds (vs 12+ seconds for Bash version)
    """)
  end

  defp show_config do
    IO.puts("EcosystemManager Configuration")
    IO.puts("===============================")

    config = Config.all()

    Enum.each(config, fn {key, value} ->
      formatted_key = key |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()
      IO.puts("#{String.pad_trailing(formatted_key, 25)}: #{inspect(value)}")
    end)

    IO.puts("\nConfiguration file: config/config.exs")
    IO.puts("Example file: config/config.example.exs")
  end

  defp show_repositories do
    IO.puts("Repository Configuration")
    IO.puts("=======================")

    # Show current repositories
    repos = Repository.all_repositories()
    configured_repos = Repository.get_configured_repositories()

    IO.puts("\nMonitored repositories (#{length(repos)}):")

    Enum.each(repos, fn repo ->
      IO.puts("  - #{repo}")
    end)

    # Show configuration source
    IO.puts("\nConfiguration source:")
    config_path = UserConfig.get_config_path()

    if File.exists?(config_path) do
      if configured_repos do
        IO.puts("  ✓ Using repositories from: #{config_path}")
      else
        IO.puts("  ✓ Config file exists: #{config_path}")
        IO.puts("    (repositories not configured, using defaults)")
      end
    else
      IO.puts("  - No config file: #{config_path}")
      IO.puts("    (using default repositories)")
    end

    # Show defaults
    defaults = Repository.default_repositories()
    IO.puts("\nDefault repositories (#{length(defaults)}):")
    IO.puts("  (used when repositories not configured)")

    IO.puts("\nTo customize:")
    IO.puts("  1. Run: ecosystem-manager init-config")
    IO.puts("  2. Edit: ~/.config/ecosystem-manager/config.exs")
    IO.puts("  3. Add repositories: [...] to the configuration")
  end

  defp init_config do
    IO.puts("Initializing user configuration...")

    # Create user config example
    case UserConfig.create_example_config() do
      {:ok, config_example} ->
        IO.puts("✓ Created example configuration: #{config_example}")
        IO.puts("  Copy to config.exs and customize your settings")
        IO.puts("  Include repositories: [...] to override default repository list")

      {:error, reason} ->
        IO.puts("✗ Failed to create config example: #{reason}")
    end
  end

  defp show_workspace_path do
    workspace_path = get_base_path()
    IO.puts(workspace_path)
  end
end
