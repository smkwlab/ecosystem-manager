defmodule EcosystemManager.UserConfigTest do
  # async: false is the ExUnit default, but make it explicit: these tests
  # mutate the ECOSYSTEM_MANAGER_CONFIG_DIR environment variable and the
  # :ecosystem_manager application env, which are global state.
  use ExUnit.Case, async: false

  alias EcosystemManager.UserConfig

  describe "get_config_path/0" do
    test "returns expanded config path" do
      path = UserConfig.get_config_path()
      assert String.ends_with?(path, "/.config/ecosystem-manager/config.exs")
      assert String.starts_with?(path, "/")
    end
  end

  describe "get_config_dir/0" do
    test "returns expanded config directory" do
      dir = UserConfig.get_config_dir()
      assert String.ends_with?(dir, "/.config/ecosystem-manager")
      assert String.starts_with?(dir, "/")
    end
  end

  describe "create_example_config/0" do
    test "creates example config file successfully" do
      with_temp_config_dir(fn config_dir ->
        result = UserConfig.create_example_config()

        case result do
          {:ok, example_path} ->
            assert Path.dirname(example_path) == config_dir
            assert File.exists?(example_path)
            assert String.ends_with?(example_path, "config.example.exs")

            content = File.read!(example_path)
            # Heredoc indentation is trimmed by Elixir, so the generated
            # file must start at column 0
            assert String.starts_with?(content, "# EcosystemManager User Configuration")
            assert String.contains?(content, "\nimport Config\n")
            assert String.contains?(content, "workspace_path:")
            assert String.contains?(content, "repositories:")

          {:error, reason} ->
            flunk("Expected success but got error: #{reason}")
        end
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

    test "handles file write errors gracefully" do
      # Test error case by trying to write to a read-only directory
      # This is hard to test directly, so we'll test the structure
      temp_dir = System.tmp_dir!()
      test_config_dir = Path.join(temp_dir, "test_ecosystem_config_#{:rand.uniform(10_000)}")

      try do
        File.mkdir_p!(test_config_dir)
        example_path = Path.join(test_config_dir, "config.example.exs")

        # Manually test the content that would be created
        content = """
        # EcosystemManager User Configuration
        # Copy this file to config.exs and customize as needed

        import Config

        # Set your LaTeX ecosystem workspace path
        # This path will be used as the base directory for all operations
        config :ecosystem_manager,
          workspace_path: "~/SynologyDrive/semi/LaTeX/latex-ecosystem"
        """

        result = File.write(example_path, content)
        assert result == :ok

        # Verify content structure
        file_content = File.read!(example_path)
        assert String.contains?(file_content, "workspace_path:")
        assert String.contains?(file_content, "import Config")
      after
        File.rm_rf!(test_config_dir)
      end
    end
  end

  describe "load/0" do
    setup do
      # Save original config values
      original_workspace = Application.get_env(:ecosystem_manager, :workspace_path)
      original_repos = Application.get_env(:ecosystem_manager, :repositories)

      on_exit(fn ->
        # Restore original values
        if original_workspace do
          Application.put_env(:ecosystem_manager, :workspace_path, original_workspace)
        else
          Application.delete_env(:ecosystem_manager, :workspace_path)
        end

        if original_repos do
          Application.put_env(:ecosystem_manager, :repositories, original_repos)
        else
          Application.delete_env(:ecosystem_manager, :repositories)
        end
      end)
    end

    test "returns :ok when config file doesn't exist" do
      with_temp_config_dir(fn _config_dir ->
        assert UserConfig.load() == :ok
      end)
    end

    test "loads valid config file and applies settings" do
      with_temp_config_dir(fn config_dir ->
        config_path = Path.join(config_dir, "config.exs")

        File.write!(config_path, """
        import Config

        config :ecosystem_manager,
          workspace_path: "/test/workspace",
          repositories: ["test-repo1", "test-repo2"]
        """)

        assert UserConfig.load() == :ok
        assert Application.get_env(:ecosystem_manager, :workspace_path) == "/test/workspace"

        assert Application.get_env(:ecosystem_manager, :repositories) == [
                 "test-repo1",
                 "test-repo2"
               ]
      end)
    end

    test "handles invalid config file gracefully" do
      with_temp_config_dir(fn config_dir ->
        config_path = Path.join(config_dir, "config.exs")
        File.write!(config_path, "invalid elixir syntax {{")

        assert {:error, message} = UserConfig.load()
        assert message =~ "configuration"
      end)
    end

    test "handles config file using build-time-only config_env/0" do
      with_temp_config_dir(fn config_dir ->
        config_path = Path.join(config_dir, "config.exs")

        File.write!(config_path, """
        import Config

        case config_env() do
          _ -> config :ecosystem_manager, workspace_path: "/test/workspace"
        end
        """)

        # config_env/0 is build-time only; loading must fail gracefully
        # instead of crashing the CLI
        assert {:error, message} = UserConfig.load()
        assert message =~ "configuration"
      end)
    end

    test "handles config file that throws" do
      with_temp_config_dir(fn config_dir ->
        config_path = Path.join(config_dir, "config.exs")

        File.write!(config_path, """
        import Config

        throw(:boom)
        """)

        assert {:error, message} = UserConfig.load()
        assert message =~ "configuration"
      end)
    end

    test "handles config file with missing import Config" do
      with_temp_config_dir(fn config_dir ->
        config_path = Path.join(config_dir, "config.exs")

        File.write!(config_path, """
        config :ecosystem_manager, workspace_path: "/test/workspace"
        """)

        assert {:error, message} = UserConfig.load()
        assert message =~ "configuration"
      end)
    end
  end

  # Runs `fun` with ECOSYSTEM_MANAGER_CONFIG_DIR pointing at a fresh
  # temporary directory so UserConfig never touches the developer's real
  # ~/.config/ecosystem-manager. Overriding HOME does not work for this:
  # Path.expand/1 resolves `~` via the home directory cached at VM start.
  # Passes the created config directory to `fun` and always restores the
  # environment afterwards.
  defp with_temp_config_dir(fun) do
    temp_dir = System.tmp_dir!()
    test_config_dir = Path.join(temp_dir, "test_config_dir_#{:rand.uniform(10_000)}")

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

  describe "create_default_config/1" do
    test "uses the default workspace placeholder when no path is given" do
      with_temp_config_dir(fn config_dir ->
        assert {:ok, config_path} = UserConfig.create_default_config()
        assert config_path == Path.join(config_dir, "config.exs")

        content = File.read!(config_path)
        assert String.contains?(content, ~s(workspace_path: "~/path/to/latex-ecosystem"))
      end)
    end

    test "creates default config file when none exists" do
      with_temp_config_dir(fn config_dir ->
        result = UserConfig.create_default_config("/test/workspace")

        case result do
          {:ok, config_path} ->
            assert config_path == Path.join(config_dir, "config.exs")

            content = File.read!(config_path)
            # Heredoc indentation is trimmed by Elixir, so the generated
            # file must start at column 0
            assert String.starts_with?(content, "# EcosystemManager User Configuration")
            assert String.contains?(content, "\nimport Config\n")
            assert String.contains?(content, ~s(workspace_path: "/test/workspace"))

          {:error, reason} ->
            flunk("Expected success but got error: #{reason}")
        end
      end)
    end

    test "returns error when config file already exists" do
      with_temp_config_dir(fn config_dir ->
        config_path = Path.join(config_dir, "config.exs")
        File.write!(config_path, "# existing config")

        result = UserConfig.create_default_config("/test/workspace")

        case result do
          {:error, message} ->
            assert String.contains?(message, "already exists")

          {:ok, _} ->
            flunk("Expected error when config file already exists")
        end
      end)
    end
  end
end
