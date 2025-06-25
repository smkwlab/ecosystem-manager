defmodule EcosystemManagerTest do
  use ExUnit.Case
  doctest EcosystemManager

  alias EcosystemManager.Repository

  describe "status/1" do
    test "returns repository list with basic configuration" do
      repos = EcosystemManager.status(include_github: false)
      assert is_list(repos)
      assert length(repos) > 0

      # Check that we have expected repositories
      repo_names = Enum.map(repos, & &1.name)
      assert "." in repo_names
      assert "texlive-ja-textlint" in repo_names
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
end
