defmodule EcosystemManager.CLI do
  @moduledoc """
  Command Line Interface for Ecosystem Manager.
  """

  alias EcosystemManager.Status

  # Behaviours for dependency injection
  @callback puts(String.t()) :: :ok
  @callback halt(non_neg_integer()) :: no_return()
  @callback get_env(String.t()) :: String.t() | nil
  @callback cwd!() :: String.t()
  @callback monotonic_time(atom()) :: integer()

  defmodule IOAdapter do
    @moduledoc """
    Default adapter for IO operations, system calls, and environment access.
    """
    @behaviour EcosystemManager.CLI
    def puts(message), do: IO.puts(message)
    def halt(code), do: System.halt(code)
    def get_env(var), do: System.get_env(var)
    def cwd!, do: File.cwd!()
    def monotonic_time(unit), do: System.monotonic_time(unit)
  end

  def main(args, adapter \\ IOAdapter) do
    args
    |> parse_args(adapter)
    |> execute(adapter)
  end

  def parse_args(args, adapter \\ IOAdapter) do
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
      base_path: get_base_path(adapter)
    }
  end

  defp execute(%{opts: opts} = config, adapter) do
    if opts[:help] do
      show_help(adapter)
    else
      continue_execute(config, adapter)
    end
  end

  defp continue_execute(%{command: "status"} = config, adapter) do
    execute_status(config, adapter)
  end

  defp continue_execute(%{command: "help"}, adapter) do
    show_help(adapter)
  end

  defp continue_execute(%{command: unknown}, adapter) do
    adapter.puts("Unknown command: #{unknown}")
    adapter.puts("Run 'ecosystem-manager help' for usage information.")
    adapter.halt(1)
  end

  defp execute_status(%{opts: opts, base_path: base_path}, adapter) do
    adapter.puts("Repository Status Overview")
    adapter.puts("")

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
    start_time = adapter.monotonic_time(:millisecond)

    # Get status
    repos = Status.get_all_status(base_path, status_opts)

    end_time = adapter.monotonic_time(:millisecond)
    elapsed = end_time - start_time

    # Format and display
    output = Status.format_status(repos, format_opts)
    adapter.puts(output)

    # Show performance info
    if opts[:fast] do
      adapter.puts("\n(Fast mode - GitHub API calls skipped)")
    end

    adapter.puts("\nCompleted in #{elapsed}ms")
  end

  def build_filters(opts) do
    []
    |> maybe_add_filter(opts[:urgent_issues], {:urgent_issues_only, true})
    |> maybe_add_filter(opts[:with_prs], {:with_prs_only, true})
    |> maybe_add_filter(opts[:needs_review], {:needs_review_only, true})
  end

  defp maybe_add_filter(filters, true, filter), do: [filter | filters]
  defp maybe_add_filter(filters, _, _), do: filters

  defp get_base_path(adapter) do
    # Try to find the ecosystem root directory
    current_dir = adapter.get_env("PWD") || adapter.cwd!()

    find_ecosystem_root(current_dir) || current_dir
  end

  def find_ecosystem_root(dir) do
    ecosystem_marker = Path.join(dir, "ecosystem-manager.sh")

    cond do
      File.exists?(ecosystem_marker) -> dir
      dir == "/" -> nil
      true -> find_ecosystem_root(Path.dirname(dir))
    end
  end

  defp show_help(adapter) do
    adapter.puts("""
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
