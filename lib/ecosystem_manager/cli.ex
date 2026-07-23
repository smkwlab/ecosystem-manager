defmodule EcosystemManager.CLI do
  @moduledoc """
  Command Line Interface for Ecosystem Manager.
  """

  alias EcosystemManager.CLI.Spec
  alias EcosystemManager.Config
  alias EcosystemManager.Repository
  alias EcosystemManager.Status
  alias EcosystemManager.UserConfig
  alias EcosystemManager.Workspace
  alias ToolKit.CLI.Exit, as: EngineExit
  alias ToolKit.CLI.Parser, as: EngineParser

  @spec main([String.t()]) :: no_return()
  def main(args) do
    args
    |> parse_args()
    |> execute()
  end

  @doc false
  def known_commands, do: Spec.command_names()

  @doc false
  def parse_args(args) do
    # strict パース・help 短絡・コマンド別オプション検証は ToolKit に委譲する。
    # サブコマンド省略時は status を実行する
    case EngineParser.parse(Spec.spec(), args, default_command: "status") do
      {:command, command, argv, opts} ->
        %{command: command, args: argv, opts: opts, base_path: resolve_base_path(opts)}

      other ->
        other
    end
  end

  defp execute(:help), do: print_help_and_exit()

  defp execute({:help_command, name}) do
    IO.puts(Spec.render_command_help(name))
    exit_with_code(0)
  end

  defp execute({:error, reason}) do
    IO.puts(:stderr, "❌ エラー: #{reason}")
    exit_with_code(1)
  end

  # `help` はコマンドとしても受ける(Parser が特別扱いするのは --help フラグのみ)
  defp execute(%{command: "help"}), do: print_help_and_exit()

  defp execute(%{} = config) do
    continue_execute(config)
    exit_with_code(0)
  end

  defp continue_execute(%{command: "status"} = config) do
    execute_status(config)
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

  # ToolKit.CLI.Parser は未知コマンドをそのまま通す仕様(dispatch 側の責務)なので、
  # この節が受けて exit 1 に落とす
  defp continue_execute(%{command: unknown}) do
    IO.puts("Unknown command: #{unknown}")
    IO.puts("Run 'ecosystem-manager help' for usage information.")
    exit_with_code(1)
  end

  defp print_help_and_exit do
    IO.puts(Spec.render_help())
    exit_with_code(0)
  end

  # テスト時は System.halt せず throw する（ToolKit.CLI.Exit の test_mode 規約）
  @spec exit_with_code(non_neg_integer()) :: no_return()
  defp exit_with_code(code), do: EngineExit.exit_with_code(:ecosystem_manager, code)

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

  @spec abort(String.t()) :: no_return()
  defp abort(message) do
    IO.puts(:stderr, message)
    exit_with_code(1)
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
