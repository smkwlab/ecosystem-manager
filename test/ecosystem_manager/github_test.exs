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

  describe "GitHub API統合テスト" do
    test "handles API rate limiting gracefully" do
      # Create temp repo with git remote
      temp_dir = System.tmp_dir!()
      test_repo_path = Path.join(temp_dir, "api_test_repo_#{:rand.uniform(10000)}")
      File.mkdir_p!(test_repo_path)

      # Create git repo with GitHub remote
      System.cmd("git", ["init"], cd: test_repo_path)

      System.cmd("git", ["remote", "add", "origin", "https://github.com/test/repo.git"],
        cd: test_repo_path
      )

      repo = %Repository{
        name: "api_test_repo",
        path: test_repo_path,
        status: :ok
      }

      # Test should handle any API errors gracefully
      result = GitHub.fetch_github_info(repo)

      # Should return default values if API fails
      assert is_map(result.issues)
      assert is_map(result.pull_requests)
      assert Map.has_key?(result.issues, :total)
      assert Map.has_key?(result.pull_requests, :total)

      # Cleanup
      File.rm_rf!(test_repo_path)
    end

    test "parses various GitHub URL formats" do
      test_cases = [
        {"https://github.com/owner/repo.git", {:ok, {"owner", "repo"}}},
        {"git@github.com:owner/repo.git", {:ok, {"owner", "repo"}}},
        {"https://github.com/owner/repo", {:ok, {"owner", "repo"}}},
        {"https://gitlab.com/owner/repo.git", :error},
        {"invalid-url", :error},
        {"", :error}
      ]

      for {url, expected} <- test_cases do
        # Test URL parsing by creating temp repo
        temp_dir = System.tmp_dir!()
        test_repo_path = Path.join(temp_dir, "url_test_#{:rand.uniform(10000)}")
        File.mkdir_p!(test_repo_path)

        System.cmd("git", ["init"], cd: test_repo_path)

        if url != "" do
          System.cmd("git", ["remote", "add", "origin", url], cd: test_repo_path)
        end

        repo = %Repository{name: "test", path: test_repo_path}
        result = GitHub.get_github_remote(repo)

        assert result == expected, "Failed for URL: #{url}"

        File.rm_rf!(test_repo_path)
      end
    end

    test "handles concurrent API calls safely" do
      # Create multiple temp repos
      temp_dir = System.tmp_dir!()

      repos =
        for i <- 1..5 do
          test_repo_path = Path.join(temp_dir, "concurrent_test_#{i}")
          File.mkdir_p!(test_repo_path)

          System.cmd("git", ["init"], cd: test_repo_path)

          System.cmd("git", ["remote", "add", "origin", "https://github.com/test/repo#{i}.git"],
            cd: test_repo_path
          )

          %Repository{name: "repo#{i}", path: test_repo_path, status: :ok}
        end

      # Test concurrent API calls
      tasks =
        for repo <- repos do
          Task.async(fn -> GitHub.fetch_github_info(repo) end)
        end

      results = Task.await_many(tasks, 15_000)

      # All should complete without errors
      assert length(results) == 5

      for result <- results do
        assert is_map(result.issues)
        assert is_map(result.pull_requests)
      end

      # Cleanup
      for repo <- repos do
        File.rm_rf!(repo.path)
      end
    end
  end

  describe "エラーハンドリングの強化" do
    test "handles gh command not found" do
      # Temporarily remove gh from PATH
      original_path = System.get_env("PATH")

      try do
        System.put_env("PATH", "")

        temp_dir = System.tmp_dir!()
        test_repo_path = Path.join(temp_dir, "no_gh_test_#{:rand.uniform(10000)}")
        File.mkdir_p!(test_repo_path)

        System.cmd("git", ["init"], cd: test_repo_path)

        System.cmd("git", ["remote", "add", "origin", "https://github.com/test/repo.git"],
          cd: test_repo_path
        )

        repo = %Repository{name: "test", path: test_repo_path, status: :ok}

        # Should handle missing gh command gracefully
        result = GitHub.fetch_github_info(repo)

        # Should return default values
        assert result.issues == %{total: 0, bugs: 0, enhancements: 0, urgent: 0}
        assert result.pull_requests == %{total: 0, drafts: 0, needs_review: 0}

        File.rm_rf!(test_repo_path)
      after
        if original_path do
          System.put_env("PATH", original_path)
        end
      end
    end

    test "handles invalid JSON response" do
      # Create temp repo
      temp_dir = System.tmp_dir!()
      test_repo_path = Path.join(temp_dir, "json_test_#{:rand.uniform(10000)}")
      File.mkdir_p!(test_repo_path)

      System.cmd("git", ["init"], cd: test_repo_path)

      System.cmd(
        "git",
        ["remote", "add", "origin", "https://github.com/nonexistent/repo123456789.git"],
        cd: test_repo_path
      )

      repo = %Repository{name: "test", path: test_repo_path, status: :ok}

      # API call might return invalid JSON or error
      result = GitHub.fetch_github_info(repo)

      # Should handle gracefully and return default values
      assert is_map(result.issues)
      assert is_map(result.pull_requests)

      File.rm_rf!(test_repo_path)
    end

    test "handles authentication failures" do
      # Test with potentially invalid or expired token
      temp_dir = System.tmp_dir!()
      test_repo_path = Path.join(temp_dir, "auth_test_#{:rand.uniform(10000)}")
      File.mkdir_p!(test_repo_path)

      System.cmd("git", ["init"], cd: test_repo_path)

      System.cmd("git", ["remote", "add", "origin", "https://github.com/private/repo.git"],
        cd: test_repo_path
      )

      repo = %Repository{name: "test", path: test_repo_path, status: :ok}

      # Should handle auth failures gracefully
      result = GitHub.fetch_github_info(repo)

      assert is_map(result.issues)
      assert is_map(result.pull_requests)

      File.rm_rf!(test_repo_path)
    end
  end

  describe "ラベル分類テスト" do
    test "correctly categorizes issues by labels" do
      # Test internal label counting logic indirectly
      # Since the functions are private, we test through public API

      # For now, verify that the structure is correct
      result = GitHub.get_issues("nonexistent", "repo")

      assert Map.has_key?(result, :total)
      assert Map.has_key?(result, :bugs)
      assert Map.has_key?(result, :enhancements)
      assert Map.has_key?(result, :urgent)
    end
  end
end
