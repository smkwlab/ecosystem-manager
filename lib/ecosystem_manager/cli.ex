defmodule EcosystemManager.CLI do
  @moduledoc """
  Command Line Interface for Ecosystem Manager.
  """

  alias EcosystemManager.Config
  alias EcosystemManager.Repository
  alias EcosystemManager.Status
  alias EcosystemManager.UserConfig
  alias EcosystemManager.Workspace

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
          max_concurrency: :integer,
          time_sort: :boolean,
          sync: :boolean,
          workspace: :string,
          name: :string,
          all: :boolean,
          list: :boolean
        ],
        aliases: [
          h: :help,
          l: :long,
          f: :fast,
          t: :time_sort,
          w: :workspace
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
      base_path: resolve_base_path(opts)
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

  defp continue_execute(%{command: "repos", opts: opts, base_path: base_path}) do
    if opts[:sync] do
      sync_repositories(opts)
    else
      show_repositories(base_path)
    end
  end

  defp continue_execute(%{command: "init-config"}) do
    init_config()
  end

  defp continue_execute(%{command: "workspace", opts: opts, base_path: base_path}) do
    if opts[:list] do
      show_workspace_list()
    else
      IO.puts(base_path)
    end
  end

  defp continue_execute(%{command: unknown}) do
    IO.puts("Unknown command: #{unknown}")
    IO.puts("Run 'ecosystem-manager help' for usage information.")

    # Use exit instead of System.halt for testability
    exit({:shutdown, 1})
  end

  defp execute_status(%{opts: opts, base_path: base_path}) do
    if opts[:all] do
      execute_status_all(opts)
    else
      IO.puts("Repository Status Overview")
      IO.puts("")
      render_status(base_path, opts)
    end
  end

  defp execute_status_all(opts) do
    case Workspace.list() do
      [] ->
        IO.puts("Repository Status Overview")
        IO.puts("(no workspaces configured; showing the current directory)")
        IO.puts("")
        render_status(current_dir(), opts)

      workspaces ->
        IO.puts("Repository Status Overview (all workspaces)")

        Enum.each(workspaces, fn ws ->
          IO.puts("\n== #{ws.name} (#{ws.path}) ==\n")
          render_status(ws.path, opts)
        end)
    end
  end

  defp render_status(base_path, opts) do
    status_opts = [
      include_github: !opts[:fast],
      max_concurrency: opts[:max_concurrency] || 8
    ]

    format_opts = [
      format: if(opts[:long], do: :long, else: :compact),
      filters: build_filters(opts),
      time_sort: opts[:time_sort] || false
    ]

    start_time = System.monotonic_time(:millisecond)
    repos = Status.get_all_status(base_path, status_opts)
    elapsed = System.monotonic_time(:millisecond) - start_time

    IO.puts(Status.format_status(repos, format_opts))

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

  # Resolve the workspace base path for this invocation:
  #   --workspace NAME    -> that registered workspace (error if unknown)
  #   otherwise           -> the workspace containing the current directory,
  #                          the single configured workspace, or the current
  #                          directory as a last resort.
  defp resolve_base_path(opts) do
    dir = current_dir()

    case Workspace.resolve(opts[:workspace], dir) do
      {:ok, ws} -> validate_workspace_path(ws.path, dir)
      {:error, reason} -> abort(reason)
      :none -> dir
    end
  end

  defp current_dir, do: System.get_env("PWD") || File.cwd!()

  # Base path for `repos --sync`: register the current directory's workspace.
  # With --workspace NAME, re-sync that registered workspace instead. Unlike
  # resolve_base_path/1 there is no single-workspace fallback, so syncing from a
  # new ecosystem registers that ecosystem rather than an existing workspace.
  defp sync_base_path(opts) do
    dir = current_dir()

    case opts[:workspace] do
      nil ->
        case Workspace.containing(dir) do
          nil -> {dir, nil}
          ws -> {ws.path, ws.name}
        end

      name ->
        case Workspace.resolve(name, dir) do
          {:ok, ws} -> {ws.path, ws.name}
          {:error, reason} -> abort(reason)
        end
    end
  end

  defp validate_workspace_path(path, current_dir) do
    expanded = Path.expand(path)

    if File.dir?(expanded) do
      expanded
    else
      IO.puts("Warning: workspace path does not exist: #{expanded}")
      IO.puts("Falling back to the current directory.")
      current_dir
    end
  end

  defp abort(message) do
    IO.puts(:stderr, message)
    exit({:shutdown, 1})
  end

  defp show_help do
    IO.puts("""
    LaTeX Thesis Environment Ecosystem Manager (Elixir Edition)

    USAGE:
        ecosystem-manager [COMMAND] [OPTIONS]

    COMMANDS:
        status            Show status of all repositories (default)
        config            Show current configuration
        repos             Show repository configuration and sources
        repos --sync      Auto-discover ecosystem repositories, write the list
                          into the user config and register the workspace
        workspace         Show the resolved workspace path
        workspace --list  List all configured workspaces
        init-config       Create example user configuration files
        help              Show this help message

    STATUS OPTIONS:
        -l, --long             Show detailed status with full information
        -f, --fast             Fast mode - skip GitHub API calls
        --all                  Show every configured workspace (grouped)
        --urgent-issues        Show only repositories with urgent issues
        --with-prs            Show only repositories with open PRs
        --needs-review        Show only repositories with PRs needing review
        --max-concurrency N   Maximum parallel operations (default: 8)

    WORKSPACE OPTIONS:
        -w, --workspace NAME   Operate on the named workspace (see workspace --list)

    EXAMPLES:
        ecosystem-manager                    # Show compact status
        ecosystem-manager status --long     # Show detailed status
        ecosystem-manager status --fast     # Quick status without GitHub API
        ecosystem-manager status --all      # Status across all workspaces
        ecosystem-manager status -w dns     # Status of the "dns" workspace
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

  defp show_repositories(base_path) do
    IO.puts("Repository Configuration")
    IO.puts("=======================")

    # Show current repositories
    repos = Repository.all_repositories(base_path)
    configured_repos = Repository.get_configured_repositories()

    IO.puts("\nMonitored repositories (#{length(repos)}):")

    Enum.each(repos, fn repo ->
      IO.puts("  - #{repo}")
    end)

    # Show configuration source
    IO.puts("\nConfiguration source:")
    config_path = UserConfig.get_config_path()

    cond do
      configured_repos ->
        IO.puts("  ✓ Using repositories from: #{config_path}")

      File.exists?(config_path) ->
        IO.puts("  ✓ Config file exists but has no repositories list: #{config_path}")
        IO.puts("    (auto-discovered under #{base_path})")

      true ->
        IO.puts("  - No config file: #{config_path}")
        IO.puts("    (auto-discovered under #{base_path})")
    end

    IO.puts("\nTo pin this list into your user config:")
    IO.puts("  ecosystem-manager repos --sync")
  end

  defp sync_repositories(opts) do
    {base_path, resolved_name} = sync_base_path(opts)
    name = opts[:name] || resolved_name || Path.basename(base_path)

    unless Workspace.valid_name?(name) do
      abort(
        "Invalid workspace name #{inspect(name)}: use letters, digits, '-' or '_' (pass --name to override)."
      )
    end

    repos = Repository.discover(base_path)

    case UserConfig.sync_workspace(name, base_path, repos) do
      {:ok, path, count} ->
        IO.puts("✓ Registered workspace \"#{name}\": #{base_path}")
        IO.puts("  #{length(repos)} repositories discovered\n")
        Enum.each(repos, fn repo -> IO.puts("  - #{repo}") end)
        print_sync_note(count, name)
        IO.puts("\nConfig: #{path}")

      {:error, reason} ->
        abort("Failed to write repositories to config: #{reason}")
    end
  end

  defp print_sync_note(count, _name) when count > 1 do
    IO.puts("\n#{count} workspaces are configured. Each workspace's repositories are")
    IO.puts("auto-discovered, so the global repositories pin was removed.")
  end

  defp print_sync_note(_count, _name) do
    IO.puts("\nReview the list and remove any entries that are not part of the")
    IO.puts("ecosystem (unrelated projects, one-off clones, etc.).")
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

  defp show_workspace_list do
    case Workspace.list() do
      [] ->
        IO.puts("No workspaces configured.")
        IO.puts("Run 'ecosystem-manager repos --sync' from a workspace to register one.")

      workspaces ->
        IO.puts("Configured workspaces (#{length(workspaces)}):")

        Enum.each(workspaces, fn ws ->
          IO.puts("  #{String.pad_trailing(ws.name, 20)} #{ws.path}")
        end)
    end
  end
end
