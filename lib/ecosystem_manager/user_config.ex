defmodule EcosystemManager.UserConfig do
  @moduledoc """
  User configuration file support for EcosystemManager.

  Loads and manages user-specific configuration from ~/.config/ecosystem-manager/config.exs

  Security note: the config file is evaluated as Elixir code with the
  privileges of the CLI user. This is acceptable for a tool reading its
  own per-user config file, but never point it at untrusted input.
  """

  @config_dir "~/.config/ecosystem-manager"
  @config_file "config.exs"

  @doc """
  Load user configuration file if it exists.
  Returns :ok if loaded successfully or if file doesn't exist.
  Returns {:error, reason} if there's a problem loading the file.
  """
  def load do
    config_path = get_config_path()

    if File.exists?(config_path) do
      try do
        # Config.Reader.read!/1 is primarily meant for build-time config,
        # but works at runtime since Elixir 1.11. The config file must
        # start with `import Config` and must not use build-time-only
        # constructs such as config_env/0 or import_config/1 (documented
        # in config.example.exs). Any error raised while evaluating it is
        # converted to {:error, reason} below.
        config_data = Config.Reader.read!(config_path)

        # Apply the configuration to the application
        if config_data[:ecosystem_manager] do
          Enum.each(config_data[:ecosystem_manager], fn {key, value} ->
            Application.put_env(:ecosystem_manager, key, value)
          end)
        end

        :ok
      rescue
        # Any raised exception (syntax errors, compile errors, and whatever
        # else evaluating user code may raise) becomes a readable message
        e ->
          {:error, "Invalid configuration file: #{Exception.message(e)}"}
      catch
        # Non-raise exits: throw/exit from a misbehaving config file must
        # not crash the CLI at startup either
        kind, reason ->
          {:error, "Failed to load configuration: #{inspect({kind, reason})}"}
      end
    else
      :ok
    end
  end

  @doc """
  Get the full path to the user configuration file.
  """
  def get_config_path do
    Path.join(get_config_dir(), @config_file)
  end

  @doc """
  Get the user configuration directory path.

  Honors the ECOSYSTEM_MANAGER_CONFIG_DIR environment variable when set
  (used by tests and useful for CI); falls back to #{@config_dir}.
  Note: HOME changes at runtime do not affect the fallback because
  Path.expand/1 resolves `~` via the home directory cached at VM start.
  """
  def get_config_dir do
    case System.get_env("ECOSYSTEM_MANAGER_CONFIG_DIR") do
      nil -> Path.expand(@config_dir)
      dir -> Path.expand(dir)
    end
  end

  @doc """
  Create example user configuration file.
  """
  def create_example_config do
    config_dir = get_config_dir()
    example_path = Path.join(config_dir, "config.example.exs")

    with :ok <- ensure_config_dir(config_dir) do
      write_example_config(example_path)
    end
  end

  defp write_example_config(example_path) do
    example_content = """
    # EcosystemManager User Configuration
    # Copy this file to config.exs and customize as needed
    #
    # This file is evaluated as Elixir code at runtime. Build-time-only
    # constructs such as config_env/0 and import_config/1 are NOT
    # available here.

    import Config

    # Set your LaTeX ecosystem workspace path
    # This path will be used as the base directory for all operations
    config :ecosystem_manager,
      workspace_path: "~/SynologyDrive/semi/LaTeX/latex-ecosystem",

      # Optional: multiple named workspaces. When set, this supersedes
      # workspace_path above. The workspace containing your current directory
      # is selected automatically; pick one explicitly with --workspace NAME.
      # `ecosystem-manager repos --sync` registers the current workspace here.
      # workspaces: [
      #   latex: "~/prj/LaTeX/latex-ecosystem",
      #   dns:   "~/prj/DNS/ecosystem"
      # ],

      # Optional: Override default repository list (single-workspace only)
      # repositories: [
      #   ".",
      #   "texlive-ja-textlint",
      #   "latex-environment",
      #   "sotsuron-template",
      #   "my-custom-repo"
      # ]

    # You can override any other settings here
    # config :ecosystem_manager,
    #   default_concurrency: 4,
    #   github_timeout: 30_000,
    #   default_format: :long
    """

    case File.write(example_path, example_content) do
      :ok ->
        {:ok, example_path}

      {:error, reason} ->
        {:error, "Failed to create example config: #{reason}"}
    end
  end

  @doc """
  Create default user configuration file if it doesn't exist.
  """
  def create_default_config(workspace_path \\ nil) do
    config_path = get_config_path()

    if File.exists?(config_path) do
      {:error, "Configuration file already exists: #{config_path}"}
    else
      with :ok <- ensure_config_dir(get_config_dir()) do
        write_default_config(config_path, workspace_path)
      end
    end
  end

  defp write_default_config(config_path, workspace_path) do
    default_content = """
    # EcosystemManager User Configuration
    # Generated on #{DateTime.utc_now() |> DateTime.to_string()}

    import Config

    # Set your LaTeX ecosystem workspace path
    config :ecosystem_manager,
      workspace_path: #{inspect(workspace_path || "~/path/to/latex-ecosystem")},
      
      # Optional: Custom repository list
      # repositories: [
      #   ".",
      #   "texlive-ja-textlint",
      #   "latex-environment",
      #   "sotsuron-template"
      # ]
    """

    case File.write(config_path, default_content) do
      :ok ->
        {:ok, config_path}

      {:error, reason} ->
        {:error, "Failed to create config: #{reason}"}
    end
  end

  @doc """
  Write the given repository list into the user config file's
  `:repositories` setting, preserving any other existing
  `:ecosystem_manager` settings (such as `workspace_path`).

  Options:

    * `:default_workspace_path` - when set and the existing config has no
      `:workspace_path`, this value is recorded as `workspace_path` so a fresh
      config generated from the workspace root is immediately usable from any
      directory. An existing `:workspace_path` is never overwritten.

  Comments in the existing file are not preserved. Returns `{:ok, path}` on
  success or `{:error, reason}` if the existing file cannot be read or the new
  file cannot be written.
  """
  def set_repositories(repositories, opts \\ []) when is_list(repositories) do
    config_path = get_config_path()

    with {:ok, existing} <- read_existing_settings(config_path),
         :ok <- ensure_config_dir(get_config_dir()) do
      merged =
        existing
        |> maybe_put_workspace_path(opts[:default_workspace_path])
        |> Keyword.put(:repositories, repositories)

      case File.write(config_path, render_config(merged)) do
        :ok -> {:ok, config_path}
        {:error, reason} -> {:error, "Failed to write config: #{:file.format_error(reason)}"}
      end
    end
  end

  defp maybe_put_workspace_path(settings, nil), do: settings

  defp maybe_put_workspace_path(settings, path) do
    if Keyword.has_key?(settings, :workspace_path) do
      settings
    else
      Keyword.put(settings, :workspace_path, path)
    end
  end

  @doc """
  Register a workspace and record its discovered repositories.

  The workspace `name` -> `path` is added to (or updated in) `:workspaces`, and
  the legacy single `:workspace_path` is dropped in favor of it. The discovered
  `repositories` list is written as the global pin only while a single
  workspace is configured; once several workspaces exist the pin is removed
  because each workspace resolves its own list via discovery.

  Returns `{:ok, path, workspace_count}` or `{:error, reason}`.
  """
  def sync_workspace(name, path, repositories) do
    config_path = get_config_path()

    with {:ok, existing} <- read_existing_settings(config_path),
         :ok <- ensure_config_dir(get_config_dir()) do
      workspaces = upsert_workspace(existing[:workspaces] || [], String.to_atom(name), path)
      count = length(workspaces)

      merged =
        existing
        |> Keyword.put(:workspaces, workspaces)
        |> Keyword.delete(:workspace_path)
        |> put_or_drop_repositories(repositories, count)

      case File.write(config_path, render_config(merged)) do
        :ok -> {:ok, config_path, count}
        {:error, reason} -> {:error, "Failed to write config: #{:file.format_error(reason)}"}
      end
    end
  end

  # Update the entry in place when the name already exists (preserving order),
  # otherwise append it so registration order is stable across syncs.
  defp upsert_workspace(workspaces, key, path) do
    if Keyword.has_key?(workspaces, key) do
      Enum.map(workspaces, fn {k, v} -> {k, if(k == key, do: path, else: v)} end)
    else
      workspaces ++ [{key, path}]
    end
  end

  defp put_or_drop_repositories(settings, repositories, 1) do
    Keyword.put(settings, :repositories, repositories)
  end

  defp put_or_drop_repositories(settings, _repositories, _count) do
    Keyword.delete(settings, :repositories)
  end

  defp read_existing_settings(config_path) do
    if File.exists?(config_path) do
      try do
        data = Config.Reader.read!(config_path)
        {:ok, Keyword.new(data[:ecosystem_manager] || [])}
      rescue
        e -> {:error, "Invalid existing configuration file: #{Exception.message(e)}"}
      end
    else
      {:ok, []}
    end
  end

  defp render_config(settings) do
    body =
      Enum.map_join(settings, ",\n", fn {key, value} ->
        "  #{key}: #{inspect(value, limit: :infinity)}"
      end)

    """
    # EcosystemManager User Configuration
    # The repositories list is managed by `ecosystem-manager repos --sync`.

    import Config

    config :ecosystem_manager,
    """ <> body <> "\n"
  end

  defp ensure_config_dir(config_dir) do
    case File.mkdir_p(config_dir) do
      :ok -> :ok
      {:error, reason} -> {:error, "Failed to create config directory: #{reason}"}
    end
  end
end
