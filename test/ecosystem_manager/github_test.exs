defmodule EcosystemManager.GitHubTest do
  use ExUnit.Case
  doctest EcosystemManager.GitHub

  alias EcosystemManager.{GitHub, Repository}

  describe "get_github_remote/1" do
    test "handles repository without git remote" do
      repo = %Repository{path: "/tmp/non-existent"}
      assert GitHub.get_github_remote(repo) == :error
    end
  end

  describe "fetch_github_info/1" do
    test "handles non-existent repository" do
      repo = %Repository{
        name: "non-existent",
        path: "/tmp/non-existent",
        status: :missing
      }

      result = GitHub.fetch_github_info(repo)
      assert result.issues == %{total: 0, bugs: 0, enhancements: 0, urgent: 0}
      assert result.pull_requests == %{total: 0, drafts: 0, needs_review: 0}
    end

    test "handles repository without GitHub remote" do
      repo = %Repository{
        name: "local-repo",
        path: "/tmp/local-repo",
        status: :ok
      }

      # Mock the exists? function to return true
      result = GitHub.fetch_github_info(repo)
      assert result.issues == %{total: 0, bugs: 0, enhancements: 0, urgent: 0}
      assert result.pull_requests == %{total: 0, drafts: 0, needs_review: 0}
    end
  end
end
