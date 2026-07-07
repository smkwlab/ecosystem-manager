defmodule EcosystemManagerTest do
  use ExUnit.Case
  doctest EcosystemManager

  alias EcosystemManager.Repository

  # Clear config that the application loads from the developer's real user
  # config at boot, so discovery-based tests do not depend on the host machine.
  setup do
    original_repos = Application.get_env(:ecosystem_manager, :repositories)
    original_org = Application.get_env(:ecosystem_manager, :ecosystem_org)
    Application.delete_env(:ecosystem_manager, :repositories)
    Application.delete_env(:ecosystem_manager, :ecosystem_org)

    on_exit(fn ->
      restore_env(:repositories, original_repos)
      restore_env(:ecosystem_org, original_org)
    end)
  end

  defp restore_env(key, nil), do: Application.delete_env(:ecosystem_manager, key)
  defp restore_env(key, value), do: Application.put_env(:ecosystem_manager, key, value)

  describe "status/1" do
    test "returns repository list with basic configuration" do
      temp_dir = System.tmp_dir!()
      workspace = Path.join(temp_dir, "status_basic_#{:rand.uniform(100_000)}")
      repo_path = Path.join(workspace, "texlive-ja-textlint")
      File.mkdir_p!(repo_path)
      System.cmd("git", ["init"], cd: repo_path)

      try do
        repos = EcosystemManager.status(base_path: workspace, include_github: false)
        assert is_list(repos)
        assert length(repos) > 0

        # Check that we discovered the workspace root and the child repository
        repo_names = Enum.map(repos, & &1.name)
        assert "." in repo_names
        assert "texlive-ja-textlint" in repo_names
      after
        File.rm_rf!(workspace)
      end
    end

    test "accepts base_path option" do
      base_path = System.tmp_dir!()
      repos = EcosystemManager.status(base_path: base_path, include_github: false)
      assert is_list(repos)
    end
  end

  describe "format_status/2" do
    test "formats repository status with compact format" do
      repos = [
        %Repository{
          name: "test-repo",
          display_name: "test-repo",
          branch: "main",
          changes: 0,
          last_commit: "abc123 1 hour ago",
          issues: %{total: 1, urgent: 0},
          pull_requests: %{total: 0, drafts: 0, needs_review: 0}
        }
      ]

      result = EcosystemManager.format_status(repos, format: :compact)
      assert is_binary(result)
      assert String.contains?(result, "test-repo")
      assert String.contains?(result, "main")
    end

    test "formats repository status with long format" do
      repos = [
        %Repository{
          name: "test-repo",
          display_name: "test-repo",
          branch: "main",
          changes: 0,
          last_commit: "abc123 1 hour ago",
          issues: %{total: 1, bugs: 0, enhancements: 1, urgent: 0},
          pull_requests: %{total: 0, drafts: 0, needs_review: 0}
        }
      ]

      result = EcosystemManager.format_status(repos, format: :long)
      assert is_binary(result)
      assert String.contains?(result, "test-repo")
    end
  end

  describe "additional coverage tests" do
    test "status/1 with default options" do
      repos = EcosystemManager.status()
      assert is_list(repos)
      assert length(repos) > 0
    end

    test "repository_status/2 with default options" do
      repo = EcosystemManager.repository_status(".")
      assert %Repository{} = repo
      assert repo.name == "."
    end

    test "repository_status/2 with custom base_path" do
      base_path = File.cwd!()
      repo = EcosystemManager.repository_status(".", base_path: base_path)
      assert %Repository{} = repo
      assert repo.name == "."
    end

    test "format_status/2 with default options" do
      repos = [
        %Repository{
          name: "test",
          display_name: "test",
          branch: "main",
          changes: 0,
          last_commit: "abc123",
          issues: %{total: 0, bugs: 0, enhancements: 0, urgent: 0},
          pull_requests: %{total: 0, drafts: 0, needs_review: 0}
        }
      ]

      result = EcosystemManager.format_status(repos)
      assert is_binary(result)
    end

    test "status/0 default function call" do
      repos = EcosystemManager.status()
      assert is_list(repos)
      assert length(repos) > 0
    end

    test "repository_status/1 single param call" do
      repo = EcosystemManager.repository_status(".")
      assert %Repository{} = repo
      assert repo.name == "."
    end

    test "format_status/1 single param call" do
      repos = [
        %Repository{
          name: "test",
          display_name: "test",
          branch: "main",
          changes: 0,
          last_commit: "abc123",
          issues: %{total: 0, bugs: 0, enhancements: 0, urgent: 0},
          pull_requests: %{total: 0, drafts: 0, needs_review: 0}
        }
      ]

      result = EcosystemManager.format_status(repos)
      assert is_binary(result)
    end
  end
end
