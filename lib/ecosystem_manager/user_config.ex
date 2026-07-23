defmodule EcosystemManager.UserConfig do
  @moduledoc """
  User configuration file support for EcosystemManager.

  Loads and manages user-specific configuration from
  ~/.config/ecosystem-manager/config.yml. The file is plain YAML data and is
  never evaluated as code. The pre-YAML `config.exs` format is not read at
  all; when only a legacy file exists, `load/0` and the write-back functions
  return migration guidance instead (see `migration_required_message/0`).

  Supported keys (unknown keys are ignored):

    * `workspace_path` — base directory for all operations (string)
    * `workspaces` — named workspaces, a `name: path` mapping
    * `repositories` — pinned repository list (list of strings)
    * `ecosystem_org` — GitHub org used to filter auto-discovery (string)
  """

  alias EcosystemManager.Workspace
  alias ToolKit.Config.Layers

  @config_dir "~/.config/ecosystem-manager"
  @config_file "config.yml"
  @example_file "config.example.yml"
  @legacy_config_file "config.exs"

  # Template for ToolKit.Config.Layers.normalize_keys/2: picks the supported
  # keys (string or atom) out of the parsed YAML and drops everything else.
  # The nil values mean "no nested structure": values are taken as-is.
  @known_keys %{
    workspace_path: nil,
    workspaces: nil,
    repositories: nil,
    ecosystem_org: nil
  }

  # Fixed rendering order of the annotated config template.
  @render_order [:workspace_path, :workspaces, :repositories, :ecosystem_org]

  @doc """
  Load the user configuration file if it exists.

  Returns `:ok` if loaded successfully or if no config file exists.
  Returns `{:error, reason}` when the file cannot be parsed, when a value has
  the wrong type, or when only a legacy `config.exs` exists (with guidance on
  migrating to `config.yml`).
  """
  def load do
    config_path = get_config_path()

    cond do
      File.exists?(config_path) -> load_and_apply(config_path)
      File.exists?(legacy_config_path()) -> {:error, migration_required_message()}
      true -> :ok
    end
  end

  defp load_and_apply(config_path) do
    with {:ok, settings} <- read_settings(config_path) do
      Enum.each(settings, fn {key, value} ->
        Application.put_env(:ecosystem_manager, key, value)
      end)

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

  defp legacy_config_path do
    Path.join(get_config_dir(), @legacy_config_file)
  end

  defp migration_required_message do
    """
    Legacy #{legacy_config_path()} found, but ecosystem-manager now reads \
    #{@config_file} only (the config.exs format is no longer evaluated).
    To migrate:
      1. Run 'ecosystem-manager init-config' to generate an annotated #{@example_file}
      2. Copy it to #{get_config_path()} and transfer your settings
         (workspace_path / workspaces / repositories / ecosystem_org)
      3. Delete the legacy config.exs\
    """
  end

  @doc """
  Create example user configuration file (#{@example_file}).
  """
  def create_example_config do
    config_dir = get_config_dir()
    example_path = Path.join(config_dir, @example_file)

    with :ok <- ensure_config_dir(config_dir) do
      write_example_config(example_path)
    end
  end

  defp write_example_config(example_path) do
    example_content = """
    # EcosystemManager User Configuration
    # Copy this file to #{@config_file} and customize as needed.
    #
    # Plain YAML data; this file is never evaluated as code. Unknown keys are
    # ignored. Supported keys: workspace_path, workspaces, repositories,
    # ecosystem_org.

    # Base directory for all operations (single-workspace setup).
    workspace_path: "~/SynologyDrive/semi/LaTeX/latex-ecosystem"

    # Optional: multiple named workspaces (name -> path). When set, this
    # supersedes workspace_path above. The workspace containing your current
    # directory is selected automatically; pick one explicitly with
    # --workspace NAME. `ecosystem-manager repos --sync` registers the
    # current workspace here.
    # workspaces:
    #   latex: "~/prj/LaTeX/latex-ecosystem"
    #   dns: "~/prj/DNS/ecosystem"

    # Optional: override the auto-discovered repository list
    # (single-workspace only).
    # repositories:
    #   - "."
    #   - "texlive-ja-textlint"
    #   - "latex-environment"
    #   - "sotsuron-template"

    # Optional: GitHub organization used to filter auto-discovered
    # repositories. When unset, it is inferred from the workspace's
    # origin remote.
    # ecosystem_org: "smkwlab"
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
    settings = [workspace_path: workspace_path || "~/path/to/latex-ecosystem"]

    case File.write(config_path, render_config(settings)) do
      :ok ->
        {:ok, config_path}

      {:error, reason} ->
        {:error, "Failed to create config: #{reason}"}
    end
  end

  @doc """
  Write the given repository list into the user config file's
  `repositories` setting, preserving any other existing settings (such as
  `workspace_path`).

  Options:

    * `:default_workspace_path` - when set and the existing config has no
      `workspace_path`, this value is recorded as `workspace_path` so a fresh
      config generated from the workspace root is immediately usable from any
      directory. An existing `workspace_path` is never overwritten.

  The file is rewritten from the annotated template (comments are part of the
  template, hand-written ones are not preserved). Returns `{:ok, path}` on
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

  The workspace `name` -> `path` is added to (or updated in) `workspaces`, and
  the legacy single `workspace_path` is dropped in favor of it. The discovered
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

  # -- Reading ----------------------------------------------------------

  defp read_existing_settings(config_path) do
    cond do
      File.exists?(config_path) -> read_settings(config_path)
      File.exists?(legacy_config_path()) -> {:error, migration_required_message()}
      true -> {:ok, []}
    end
  end

  defp read_settings(config_path) do
    case YamlElixir.read_from_file(config_path) do
      {:ok, raw} when is_map(raw) ->
        normalize_settings(raw, config_path)

      # An empty file parses to nil; treat it as "no settings"
      {:ok, nil} ->
        {:ok, []}

      {:ok, _other} ->
        {:error,
         "Invalid configuration file #{config_path}: top level must be a mapping of settings"}

      {:error, error} ->
        {:error, "Invalid configuration file #{config_path}: #{Exception.message(error)}"}
    end
  end

  defp normalize_settings(raw, config_path) do
    raw
    |> Layers.normalize_keys(@known_keys)
    |> Enum.sort_by(fn {key, _value} -> Enum.find_index(@render_order, &(&1 == key)) end)
    |> Enum.reduce_while({:ok, []}, fn {key, value}, {:ok, acc} ->
      case normalize_setting(key, value) do
        {:ok, normalized} ->
          {:cont, {:ok, [{key, normalized} | acc]}}

        {:error, message} ->
          {:halt, {:error, "Invalid configuration file #{config_path}: #{message}"}}
      end
    end)
    |> case do
      {:ok, settings} -> {:ok, Enum.reverse(settings)}
      {:error, _} = error -> error
    end
  end

  defp normalize_setting(:workspace_path, value) when is_binary(value), do: {:ok, value}
  defp normalize_setting(:ecosystem_org, value) when is_binary(value), do: {:ok, value}

  defp normalize_setting(:repositories, value) do
    if is_list(value) and Enum.all?(value, &is_binary/1) do
      {:ok, value}
    else
      {:error, "'repositories' must be a list of strings"}
    end
  end

  defp normalize_setting(:workspaces, value) when is_map(value) do
    cond do
      not Enum.all?(value, fn {name, path} -> is_binary(name) and is_binary(path) end) ->
        {:error, "'workspaces' must be a mapping of name to path"}

      invalid = Enum.find(Map.keys(value), &(not Workspace.valid_name?(&1))) ->
        {:error,
         "invalid workspace name #{inspect(invalid)} in 'workspaces' " <>
           "(use 1-64 letters, digits, '-' or '_')"}

      true ->
        # Keep the internal representation a keyword list (what Workspace and
        # the write-back path expect). YAML mappings carry no reliable order,
        # so sort by name for determinism. Workspace.valid_name?/1 above
        # bounds the atoms created here to short, well-formed identifiers, so
        # a hand-edited config cannot grow the atom table unboundedly.
        workspaces =
          value
          |> Enum.sort()
          |> Enum.map(fn {name, path} -> {String.to_atom(name), path} end)

        {:ok, workspaces}
    end
  end

  defp normalize_setting(:workspaces, _value) do
    {:error, "'workspaces' must be a mapping of name to path"}
  end

  defp normalize_setting(key, _value) do
    {:error, "'#{key}' must be a string"}
  end

  # -- Rendering --------------------------------------------------------

  # Renders the annotated config.yml. Comments are part of the template (the
  # org convention treats them as part of the design), so a rewrite by
  # `repos --sync` keeps the file self-documenting; hand-written comments are
  # not preserved.
  defp render_config(settings) do
    sections =
      @render_order
      |> Enum.filter(&Keyword.has_key?(settings, &1))
      |> Enum.map(&render_section(&1, Keyword.fetch!(settings, &1)))

    Enum.join([header() | sections], "\n")
  end

  defp header do
    """
    # EcosystemManager User Configuration
    # Plain YAML data; this file is never evaluated as code.
    # Rewritten from a fixed template by `ecosystem-manager repos --sync`
    # (hand-written comments are not preserved).
    """
  end

  defp render_section(:workspace_path, value) do
    """
    # Base directory for all operations (single-workspace setup).
    workspace_path: #{yaml_string(value)}
    """
  end

  defp render_section(:workspaces, workspaces) do
    entries =
      Enum.map_join(workspaces, "\n", fn {name, path} ->
        "  #{yaml_string(to_string(name))}: #{yaml_string(path)}"
      end)

    """
    # Named workspaces (name -> path); supersedes workspace_path. The
    # workspace containing the current directory is selected automatically;
    # pick one explicitly with --workspace NAME. Managed by
    # `ecosystem-manager repos --sync`.
    workspaces:
    """ <> entries <> "\n"
  end

  defp render_section(:repositories, repositories) do
    entries = Enum.map_join(repositories, "\n", fn repo -> "  - #{yaml_string(repo)}" end)

    """
    # Pinned repository list (single-workspace only). Managed by
    # `ecosystem-manager repos --sync`; remove entries that are not part of
    # the ecosystem.
    repositories:
    """ <> entries <> "\n"
  end

  defp render_section(:ecosystem_org, value) do
    """
    # GitHub organization used to filter auto-discovered repositories
    # (inferred from the workspace's origin remote when unset).
    ecosystem_org: #{yaml_string(value)}
    """
  end

  # Values are paths, workspace names and repository names; inspect/1 yields
  # a double-quoted string whose escapes are valid YAML for these inputs.
  defp yaml_string(value) when is_binary(value), do: inspect(value)

  defp ensure_config_dir(config_dir) do
    case File.mkdir_p(config_dir) do
      :ok -> :ok
      {:error, reason} -> {:error, "Failed to create config directory: #{reason}"}
    end
  end
end
