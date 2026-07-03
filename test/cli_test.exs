defmodule EcosystemManager.CLITest do
  use ExUnit.Case
  doctest EcosystemManager.CLI

  alias EcosystemManager.CLI

  describe "parse_args/1" do
    test "parses help flag" do
      result = CLI.parse_args(["--help"])
      assert result.opts[:help] == true
      assert result.command == "status"
    end

    test "parses command" do
      result = CLI.parse_args(["status"])
      assert result.command == "status"
    end

    test "parses options" do
      result = CLI.parse_args(["status", "--long", "--fast"])
      assert result.opts[:long] == true
      assert result.opts[:fast] == true
    end

    test "defaults to status command" do
      result = CLI.parse_args([])
      assert result.command == "status"
    end

    test "handles unknown command" do
      result = CLI.parse_args(["unknown"])
      assert result.command == "unknown"
    end

    test "parses max_concurrency option" do
      result = CLI.parse_args(["status", "--max-concurrency", "12"])
      assert result.opts[:max_concurrency] == 12
    end

    test "parses filter options" do
      result = CLI.parse_args(["status", "--urgent-issues", "--with-prs", "--needs-review"])
      assert result.opts[:urgent_issues] == true
      assert result.opts[:with_prs] == true
      assert result.opts[:needs_review] == true
    end

    test "handles aliases" do
      result = CLI.parse_args(["-h", "-l", "-f"])
      assert result.opts[:help] == true
      assert result.opts[:long] == true
      assert result.opts[:fast] == true
    end

    test "parses time sort option" do
      result = CLI.parse_args(["status", "--time-sort"])
      assert result.opts[:time_sort] == true
    end

    test "parses time sort alias" do
      result = CLI.parse_args(["status", "-t"])
      assert result.opts[:time_sort] == true
    end

    test "includes base_path in result" do
      result = CLI.parse_args(["status"])
      assert is_binary(result.base_path)
    end
  end

  describe "build_filters/1" do
    test "builds empty filters for no options" do
      filters = CLI.build_filters([])
      assert filters == []
    end

    test "builds filters for urgent issues" do
      filters = CLI.build_filters(urgent_issues: true)
      assert {:urgent_issues_only, true} in filters
    end

    test "builds filters for PRs" do
      filters = CLI.build_filters(with_prs: true)
      assert {:with_prs_only, true} in filters
    end

    test "builds filters for needs review" do
      filters = CLI.build_filters(needs_review: true)
      assert {:needs_review_only, true} in filters
    end

    test "builds multiple filters" do
      filters = CLI.build_filters(urgent_issues: true, with_prs: true)
      assert {:urgent_issues_only, true} in filters
      assert {:with_prs_only, true} in filters
    end

    test "ignores false values" do
      filters = CLI.build_filters(urgent_issues: false, with_prs: true)
      assert {:urgent_issues_only, true} not in filters
      assert {:with_prs_only, true} in filters
    end
  end

  describe "find_ecosystem_root/1" do
    test "finds root with marker file" do
      temp_dir = System.tmp_dir!()
      test_dir = Path.join(temp_dir, "test_ecosystem_#{:rand.uniform(10_000)}")
      File.mkdir_p!(test_dir)
      marker_file = Path.join(test_dir, "ecosystem-manager.sh")
      File.write!(marker_file, "#!/bin/bash\necho test")

      try do
        result = CLI.find_ecosystem_root(test_dir)
        assert result == test_dir
      after
        File.rm_rf!(test_dir)
      end
    end

    test "returns nil when no marker found" do
      temp_dir = System.tmp_dir!()
      test_dir = Path.join(temp_dir, "no_marker_#{:rand.uniform(10_000)}")
      File.mkdir_p!(test_dir)

      try do
        result = CLI.find_ecosystem_root(test_dir)
        assert result == nil
      after
        File.rm_rf!(test_dir)
      end
    end

    test "traverses up directory tree" do
      temp_dir = System.tmp_dir!()
      deep_path = Path.join(temp_dir, "level1/level2/level3/level4")
      File.mkdir_p!(deep_path)
      marker_path = Path.join(temp_dir, "level1/level2")
      marker_file = Path.join(marker_path, "ecosystem-manager.sh")
      File.write!(marker_file, "#!/bin/bash\necho test")

      try do
        result = CLI.find_ecosystem_root(deep_path)
        assert result == marker_path
      after
        File.rm_rf!(Path.join(temp_dir, "level1"))
      end
    end
  end

  describe "get_base_path with workspace_path config" do
    test "base_path uses find_ecosystem_root when workspace_path not configured" do
      # With default config (workspace_path: nil), it should use current directory logic
      result = CLI.parse_args(["status"])
      assert is_binary(result.base_path)
    end

    test "base_path validation" do
      # Parse args should always provide a base_path
      result = CLI.parse_args(["status"])
      assert Map.has_key?(result, :base_path)
      assert is_binary(result.base_path)

      # If it's not the current directory, it should be an absolute path
      if result.base_path != "." do
        assert Path.type(result.base_path) == :absolute
      end
    end
  end

  describe "argument parsing edge cases" do
    test "handles empty string arguments" do
      result = CLI.parse_args([""])
      assert result.command == ""
      assert is_list(result.opts)
      assert is_binary(result.base_path)
    end

    test "handles max-concurrency without value" do
      result = CLI.parse_args(["status", "--max-concurrency"])
      assert result.command == "status"
      assert is_nil(result.opts[:max_concurrency])
    end

    test "handles unknown flags" do
      result = CLI.parse_args(["status", "--unknown-flag"])
      assert result.command == "status"
      assert is_list(result.opts)
    end
  end

  describe "all supported commands" do
    test "parses config command" do
      result = CLI.parse_args(["config"])
      assert result.command == "config"
    end

    test "parses repos command" do
      result = CLI.parse_args(["repos"])
      assert result.command == "repos"
    end

    test "parses init-config command" do
      result = CLI.parse_args(["init-config"])
      assert result.command == "init-config"
    end

    test "parses help command" do
      result = CLI.parse_args(["help"])
      assert result.command == "help"
    end

    test "parses workspace command" do
      result = CLI.parse_args(["workspace"])
      assert result.command == "workspace"
    end
  end

  describe "filter combinations" do
    test "handles all filter combinations" do
      filter_opts = [
        [urgent_issues: true],
        [with_prs: true],
        [needs_review: true],
        [urgent_issues: true, with_prs: true],
        [urgent_issues: true, needs_review: true],
        [with_prs: true, needs_review: true],
        [urgent_issues: true, with_prs: true, needs_review: true]
      ]

      for opts <- filter_opts do
        filters = CLI.build_filters(opts)
        assert is_list(filters)
        expected_count = Enum.count(opts, fn {_k, v} -> v end)
        assert length(filters) == expected_count
      end
    end
  end

  describe "main/1 integration" do
    test "executes help command" do
      # Capture IO to verify output
      result =
        ExUnit.CaptureIO.capture_io(fn ->
          CLI.main(["help"])
        end)

      assert String.contains?(result, "LaTeX Thesis Environment Ecosystem Manager")
      assert String.contains?(result, "USAGE:")
      assert String.contains?(result, "COMMANDS:")
    end

    test "executes help flag" do
      result =
        ExUnit.CaptureIO.capture_io(fn ->
          CLI.main(["--help"])
        end)

      assert String.contains?(result, "LaTeX Thesis Environment Ecosystem Manager")
    end

    test "executes config command" do
      result =
        ExUnit.CaptureIO.capture_io(fn ->
          CLI.main(["config"])
        end)

      assert String.contains?(result, "EcosystemManager Configuration")
    end

    test "executes repos command" do
      result =
        ExUnit.CaptureIO.capture_io(fn ->
          CLI.main(["repos"])
        end)

      assert String.contains?(result, "Repository Configuration")
    end

    test "executes init-config command" do
      result =
        ExUnit.CaptureIO.capture_io(fn ->
          CLI.main(["init-config"])
        end)

      assert String.contains?(result, "Initializing user configuration")
    end

    test "executes workspace command" do
      result =
        ExUnit.CaptureIO.capture_io(fn ->
          CLI.main(["workspace"])
        end)

      # Should output a path (either configured workspace_path or detected base_path)
      trimmed_result = String.trim(result)
      assert trimmed_result != ""
      assert String.length(trimmed_result) > 0
      # Should be an absolute path
      assert String.starts_with?(trimmed_result, "/")
    end

    test "executes status command with fast mode" do
      result =
        ExUnit.CaptureIO.capture_io(fn ->
          CLI.main(["status", "--fast"])
        end)

      assert String.contains?(result, "Repository Status Overview")
      assert String.contains?(result, "Fast mode")
    end

    test "handles unknown command with exit" do
      result =
        ExUnit.CaptureIO.capture_io(fn ->
          assert catch_exit(CLI.main(["unknown"])) == {:shutdown, 1}
        end)

      assert String.contains?(result, "Unknown command: unknown")
      assert String.contains?(result, "Run 'ecosystem-manager help' for usage information.")
    end
  end
end
