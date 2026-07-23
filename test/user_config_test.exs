defmodule EcosystemManager.UserConfigTest do
  # async: false is the ExUnit default, but make it explicit: these tests
  # mutate the ECOSYSTEM_MANAGER_CONFIG_DIR environment variable and the
  # :ecosystem_manager application env, which are global state.
  use ExUnit.Case, async: false

  alias EcosystemManager.UserConfig

  describe "get_config_path/0" do
    test "returns expanded config path" do
      path = UserConfig.get_config_path()
      assert String.ends_with?(path, "/config.yml")
      assert String.starts_with?(path, "/")
    end
  end

  describe "get_config_dir/0" do
    test "returns an expanded absolute config directory" do
      dir = UserConfig.get_config_dir()
      assert String.starts_with?(dir, "/")
    end
  end

  describe "create_example_config/0" do
    test "creates an annotated YAML example that parses" do
      with_temp_config_dir(fn config_dir ->
        assert {:ok, example_path} = UserConfig.create_example_config()

        assert Path.dirname(example_path) == config_dir
        assert String.ends_with?(example_path, "config.example.yml")

        content = File.read!(example_path)
        assert String.starts_with?(content, "# EcosystemManager User Configuration")
        assert String.contains?(content, "workspace_path:")
        assert String.contains?(content, "# repositories:")
        assert String.contains?(content, "# workspaces:")
        assert String.contains?(content, "# ecosystem_org:")

        # The example (active keys + commented-out options) must be valid YAML
        assert {:ok, parsed} = YamlElixir.read_from_file(example_path)
        assert is_map(parsed)
        assert Map.has_key?(parsed, "workspace_path")
      end)
    end

    test "returns error when the config directory cannot be created" do
      # Point the config dir below a regular file so mkdir_p reliably
      # fails with :enotdir on every platform
      temp_dir = System.tmp_dir!()
      blocker = Path.join(temp_dir, "blocker_#{:rand.uniform(10_000)}")
      File.write!(blocker, "not a directory")

      original = System.get_env("ECOSYSTEM_MANAGER_CONFIG_DIR")

      try do
        System.put_env("ECOSYSTEM_MANAGER_CONFIG_DIR", Path.join(blocker, "nested"))

        assert {:error, message} = UserConfig.create_example_config()
        assert message =~ "config"

        assert {:error, message} = UserConfig.create_default_config("/test/workspace")
        assert message =~ "config"
      after
        if original do
          System.put_env("ECOSYSTEM_MANAGER_CONFIG_DIR", original)
        else
          System.delete_env("ECOSYSTEM_MANAGER_CONFIG_DIR")
        end

        File.rm(blocker)
      end
    end
  end

  describe "load/0" do
    setup do
      snapshot_app_env()
    end

    test "returns :ok when no config file exists" do
      with_temp_config_dir(fn _config_dir ->
        assert UserConfig.load() == :ok
      end)
    end

    test "loads valid config.yml and applies settings" do
      with_temp_config_dir(fn config_dir ->
        File.write!(Path.join(config_dir, "config.yml"), """
        workspace_path: "/test/workspace"
        repositories:
          - "test-repo1"
          - "test-repo2"
        ecosystem_org: "smkwlab"
        """)

        assert UserConfig.load() == :ok
        assert Application.get_env(:ecosystem_manager, :workspace_path) == "/test/workspace"
        assert Application.get_env(:ecosystem_manager, :ecosystem_org) == "smkwlab"

        assert Application.get_env(:ecosystem_manager, :repositories) == [
                 "test-repo1",
                 "test-repo2"
               ]
      end)
    end

    test "loads workspaces mapping as a keyword list sorted by name" do
      with_temp_config_dir(fn config_dir ->
        File.write!(Path.join(config_dir, "config.yml"), """
        workspaces:
          latex: "/home/u/latex"
          dns: "/home/u/dns"
        """)

        assert UserConfig.load() == :ok

        assert Application.get_env(:ecosystem_manager, :workspaces) == [
                 dns: "/home/u/dns",
                 latex: "/home/u/latex"
               ]
      end)
    end

    test "ignores unknown keys" do
      with_temp_config_dir(fn config_dir ->
        File.write!(Path.join(config_dir, "config.yml"), """
        workspace_path: "/test/workspace"
        default_concurrency: 4
        """)

        assert UserConfig.load() == :ok
        # Unknown keys never reach the application env (getter default: 8)
        assert EcosystemManager.Config.default_concurrency() == 8
      end)
    end

    test "returns an error for invalid YAML" do
      with_temp_config_dir(fn config_dir ->
        File.write!(Path.join(config_dir, "config.yml"), "workspaces: {{{")

        assert {:error, message} = UserConfig.load()
        assert message =~ "configuration"
      end)
    end

    test "returns an error when the top level is not a mapping" do
      with_temp_config_dir(fn config_dir ->
        File.write!(Path.join(config_dir, "config.yml"), """
        - one
        - two
        """)

        assert {:error, message} = UserConfig.load()
        assert message =~ "mapping"
      end)
    end

    test "rejects invalid workspace names" do
      with_temp_config_dir(fn config_dir ->
        File.write!(Path.join(config_dir, "config.yml"), """
        workspaces:
          "bad name!": "/home/u/latex"
        """)

        assert {:error, message} = UserConfig.load()
        assert message =~ "workspace name"
      end)
    end

    test "returns an error for wrongly typed values" do
      with_temp_config_dir(fn config_dir ->
        File.write!(Path.join(config_dir, "config.yml"), """
        repositories: "not-a-list"
        """)

        assert {:error, message} = UserConfig.load()
        assert message =~ "repositories"
      end)
    end

    test "returns migration guidance when only a legacy config.exs exists" do
      with_temp_config_dir(fn config_dir ->
        File.write!(Path.join(config_dir, "config.exs"), """
        import Config
        config :ecosystem_manager, workspace_path: "/legacy"
        """)

        assert {:error, message} = UserConfig.load()
        assert message =~ "config.exs"
        assert message =~ "config.yml"
        assert message =~ "init-config"
        # The legacy file must not be evaluated
        assert Application.get_env(:ecosystem_manager, :workspace_path) != "/legacy"
      end)
    end

    test "ignores a leftover config.exs once config.yml exists" do
      with_temp_config_dir(fn config_dir ->
        File.write!(Path.join(config_dir, "config.exs"), """
        import Config
        config :ecosystem_manager, workspace_path: "/legacy"
        """)

        File.write!(Path.join(config_dir, "config.yml"), """
        workspace_path: "/current"
        """)

        assert UserConfig.load() == :ok
        assert Application.get_env(:ecosystem_manager, :workspace_path) == "/current"
      end)
    end
  end

  describe "create_default_config/1" do
    test "uses the default workspace placeholder when no path is given" do
      with_temp_config_dir(fn config_dir ->
        assert {:ok, config_path} = UserConfig.create_default_config()
        assert config_path == Path.join(config_dir, "config.yml")

        content = File.read!(config_path)
        assert String.contains?(content, ~s(workspace_path: "~/path/to/latex-ecosystem"))
      end)
    end

    test "creates an annotated default config that reloads" do
      with_temp_config_dir(fn config_dir ->
        assert {:ok, config_path} = UserConfig.create_default_config("/test/workspace")
        assert config_path == Path.join(config_dir, "config.yml")

        content = File.read!(config_path)
        assert String.starts_with?(content, "# EcosystemManager User Configuration")
        assert String.contains?(content, ~s(workspace_path: "/test/workspace"))

        assert {:ok, parsed} = YamlElixir.read_from_file(config_path)
        assert parsed["workspace_path"] == "/test/workspace"
      end)
    end

    test "returns error when config file already exists" do
      with_temp_config_dir(fn config_dir ->
        File.write!(Path.join(config_dir, "config.yml"), "# existing config")

        assert {:error, message} = UserConfig.create_default_config("/test/workspace")
        assert String.contains?(message, "already exists")
      end)
    end
  end

  describe "set_repositories/2" do
    setup do
      snapshot_app_env()
    end

    test "writes an annotated repositories list that round-trips" do
      with_temp_config_dir(fn config_dir ->
        assert {:ok, config_path} = UserConfig.set_repositories([".", "aldc", "wr-template"])
        assert config_path == Path.join(config_dir, "config.yml")

        content = File.read!(config_path)
        # Comments are part of the design: the generated YAML is annotated
        assert String.starts_with?(content, "# EcosystemManager User Configuration")
        assert String.contains?(content, "repositories:")
        assert String.contains?(content, "aldc")

        # The generated file must be valid and round-trip through the loader
        assert UserConfig.load() == :ok

        assert Application.get_env(:ecosystem_manager, :repositories) == [
                 ".",
                 "aldc",
                 "wr-template"
               ]
      end)
    end

    test "preserves existing settings such as workspace_path" do
      with_temp_config_dir(fn config_dir ->
        config_path = Path.join(config_dir, "config.yml")

        File.write!(config_path, """
        workspace_path: "/existing/workspace"
        repositories:
          - "old-repo"
        """)

        assert {:ok, ^config_path} = UserConfig.set_repositories([".", "aldc"])

        content = File.read!(config_path)
        assert String.contains?(content, ~s(workspace_path: "/existing/workspace"))
        assert String.contains?(content, "aldc")
        refute String.contains?(content, "old-repo")

        assert UserConfig.load() == :ok
        assert Application.get_env(:ecosystem_manager, :workspace_path) == "/existing/workspace"
        assert Application.get_env(:ecosystem_manager, :repositories) == [".", "aldc"]
      end)
    end

    test "returns an error when the existing config is invalid" do
      with_temp_config_dir(fn config_dir ->
        File.write!(Path.join(config_dir, "config.yml"), "repositories: {{{")

        assert {:error, message} = UserConfig.set_repositories([".", "aldc"])
        assert message =~ "configuration"
      end)
    end

    test "returns migration guidance when only a legacy config.exs exists" do
      with_temp_config_dir(fn config_dir ->
        File.write!(Path.join(config_dir, "config.exs"), """
        import Config
        config :ecosystem_manager, workspace_path: "/legacy"
        """)

        assert {:error, message} = UserConfig.set_repositories([".", "aldc"])
        assert message =~ "config.exs"
        assert message =~ "init-config"
      end)
    end

    test "seeds workspace_path from :default_workspace_path when config is fresh" do
      with_temp_config_dir(fn _config_dir ->
        assert {:ok, _path} =
                 UserConfig.set_repositories([".", "aldc"],
                   default_workspace_path: "/detected/workspace"
                 )

        assert UserConfig.load() == :ok
        assert Application.get_env(:ecosystem_manager, :workspace_path) == "/detected/workspace"
        assert Application.get_env(:ecosystem_manager, :repositories) == [".", "aldc"]
      end)
    end

    test "does not override an existing workspace_path" do
      with_temp_config_dir(fn config_dir ->
        File.write!(Path.join(config_dir, "config.yml"), """
        workspace_path: "/existing/workspace"
        """)

        assert {:ok, _path} =
                 UserConfig.set_repositories([".", "aldc"],
                   default_workspace_path: "/detected/workspace"
                 )

        assert UserConfig.load() == :ok
        assert Application.get_env(:ecosystem_manager, :workspace_path) == "/existing/workspace"
      end)
    end
  end

  describe "sync_workspace/3" do
    setup do
      snapshot_app_env()
    end

    test "registers the first workspace and pins its discovered repositories" do
      with_temp_config_dir(fn _config_dir ->
        assert {:ok, path, 1} =
                 UserConfig.sync_workspace("latex", "/home/u/latex", [".", "aldc"])

        # Write-back keeps the annotated template
        content = File.read!(path)
        assert String.starts_with?(content, "# EcosystemManager User Configuration")

        assert UserConfig.load() == :ok
        assert Application.get_env(:ecosystem_manager, :workspaces) == [latex: "/home/u/latex"]
        assert Application.get_env(:ecosystem_manager, :repositories) == [".", "aldc"]
      end)
    end

    test "migrates a legacy workspace_path away in favor of workspaces" do
      with_temp_config_dir(fn config_dir ->
        File.write!(Path.join(config_dir, "config.yml"), """
        workspace_path: "/home/u/latex"
        """)

        assert {:ok, path, 1} =
                 UserConfig.sync_workspace("latex", "/home/u/latex", ["."])

        # load/0 never deletes keys already in the application env, so assert on
        # the generated file: workspace_path must be gone, replaced by workspaces.
        content = File.read!(path)
        refute String.contains?(content, "workspace_path:")
        assert String.contains?(content, "workspaces:")

        assert UserConfig.load() == :ok
        assert Application.get_env(:ecosystem_manager, :workspaces) == [latex: "/home/u/latex"]
      end)
    end

    test "adds a second workspace and drops the global repositories pin" do
      with_temp_config_dir(fn config_dir ->
        File.write!(Path.join(config_dir, "config.yml"), """
        workspaces:
          latex: "/home/u/latex"
        repositories:
          - "."
          - "aldc"
        """)

        assert {:ok, path, 2} =
                 UserConfig.sync_workspace("dns", "/home/u/dns", [".", "zone"])

        # The global repositories pin must be dropped from the generated file
        # (load/0 does not delete pre-existing application env keys).
        content = File.read!(path)
        refute String.contains?(content, "repositories:")

        assert UserConfig.load() == :ok

        # Workspaces from YAML are normalized sorted by name
        assert Application.get_env(:ecosystem_manager, :workspaces) == [
                 dns: "/home/u/dns",
                 latex: "/home/u/latex"
               ]
      end)
    end

    test "updating an existing workspace keeps the count at one" do
      with_temp_config_dir(fn _config_dir ->
        assert {:ok, _path, 1} = UserConfig.sync_workspace("latex", "/old/path", ["."])
        assert {:ok, _path, 1} = UserConfig.sync_workspace("latex", "/new/path", ["."])

        assert UserConfig.load() == :ok
        assert Application.get_env(:ecosystem_manager, :workspaces) == [latex: "/new/path"]
      end)
    end

    test "returns migration guidance when only a legacy config.exs exists" do
      with_temp_config_dir(fn config_dir ->
        File.write!(Path.join(config_dir, "config.exs"), """
        import Config
        config :ecosystem_manager, workspaces: [latex: "/legacy"]
        """)

        assert {:error, message} = UserConfig.sync_workspace("latex", "/home/u/latex", ["."])
        assert message =~ "config.exs"
        assert message =~ "init-config"
      end)
    end
  end

  defp restore_env(key, nil), do: Application.delete_env(:ecosystem_manager, key)
  defp restore_env(key, value), do: Application.put_env(:ecosystem_manager, key, value)

  # Snapshot the :ecosystem_manager application env keys these tests mutate
  # (via load/0) and restore them afterwards so nothing leaks between files.
  defp snapshot_app_env do
    original =
      for key <- [:workspace_path, :workspaces, :repositories, :ecosystem_org] do
        {key, Application.get_env(:ecosystem_manager, key)}
      end

    on_exit(fn ->
      Enum.each(original, fn {key, value} -> restore_env(key, value) end)
    end)

    :ok
  end

  # Runs `fun` with ECOSYSTEM_MANAGER_CONFIG_DIR pointing at a fresh
  # temporary directory so UserConfig never touches the developer's real
  # ~/.config/ecosystem-manager. Overriding HOME does not work for this:
  # Path.expand/1 resolves `~` via the home directory cached at VM start.
  # Passes the created config directory to `fun` and always restores the
  # environment afterwards.
  defp with_temp_config_dir(fun) do
    temp_dir = System.tmp_dir!()

    test_config_dir =
      Path.join(temp_dir, "test_config_dir_#{System.unique_integer([:positive])}")

    original = System.get_env("ECOSYSTEM_MANAGER_CONFIG_DIR")

    try do
      System.put_env("ECOSYSTEM_MANAGER_CONFIG_DIR", test_config_dir)
      File.mkdir_p!(test_config_dir)
      fun.(test_config_dir)
    after
      if original do
        System.put_env("ECOSYSTEM_MANAGER_CONFIG_DIR", original)
      else
        System.delete_env("ECOSYSTEM_MANAGER_CONFIG_DIR")
      end

      File.rm_rf!(test_config_dir)
    end
  end
end
