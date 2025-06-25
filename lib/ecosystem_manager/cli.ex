defmodule EcosystemManager.CLI do
  @moduledoc """
  Command Line Interface for Ecosystem Manager.
  """

  alias EcosystemManager.Status

  def main(args) do
    args
    |> parse_args()
    |> execute()
  end

  defp parse_args(args) do
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

  defp continue_execute(%{command: unknown}) do
    IO.puts("Unknown command: #{unknown}")
    IO.puts("Run 'ecosystem-manager help' for usage information.")
    System.halt(1)
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

  defp build_filters(opts) do
    []
    |> maybe_add_filter(opts[:urgent_issues], {:urgent_issues_only, true})
    |> maybe_add_filter(opts[:with_prs], {:with_prs_only, true})
    |> maybe_add_filter(opts[:needs_review], {:needs_review_only, true})
  end

  defp maybe_add_filter(filters, true, filter), do: [filter | filters]
  defp maybe_add_filter(filters, _, _), do: filters

  defp get_base_path do
    # Try to find the ecosystem root directory
    current_dir = System.get_env("PWD") || File.cwd!()

    find_ecosystem_root(current_dir) || current_dir
  end

  defp find_ecosystem_root(dir) do
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

    PERFORMANCE:
        This Elixir version uses parallel processing to significantly improve
        performance compared to the original Bash script.
        
        Expected performance:
        - Fast mode:     ~1-2 seconds 
        - Full mode:     ~2-4 seconds (vs 12+ seconds for Bash version)
    """)
  end
end
