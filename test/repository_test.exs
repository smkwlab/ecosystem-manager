defmodule EcosystemManager.RepositoryTest do
  use ExUnit.Case
  doctest EcosystemManager.Repository

  alias EcosystemManager.Repository

  # The application loads the developer's real user config at boot, which may
  # set :repositories / :ecosystem_org. Clear them so discovery-based tests do
  # not depend on the host machine's configuration.
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

  describe "new function" do
    test "creates repository struct for current directory" do
      repo = Repository.new(".", "/test/path")
      assert repo.name == "."
      assert repo.path == "/test/path"
      # "." is the workspace root; its display name is the workspace dir name
      assert repo.display_name == "path"
      assert repo.status == :ok
    end

    test "derives the current-directory display name from the workspace path" do
      assert Repository.new(".", "/home/u/latex-ecosystem").display_name == "latex-ecosystem"
      assert Repository.new(".", "/home/u/DNS/ecosystem").display_name == "ecosystem"
    end

    test "current-directory display name is deterministic (independent of cwd)" do
      # A relative base path must not be resolved against the working directory.
      assert Repository.new(".", "some/dir").display_name == "dir"
    end

    test "creates repository struct for named directory" do
      repo = Repository.new("test-repo", "/base/path")
      assert repo.name == "test-repo"
      assert repo.path == "/base/path/test-repo"
      assert repo.display_name == "test-repo"
      assert repo.status == :ok
    end
  end

  describe "exists? function" do
    test "identifies existing git repositories" do
      temp_dir = System.tmp_dir!()
      git_repo = Path.join(temp_dir, "git_test_#{:rand.uniform(10000)}")
      File.mkdir_p!(git_repo)
      System.cmd("git", ["init"], cd: git_repo)

      try do
        repo = Repository.new("test", git_repo)
        repo = %{repo | path: git_repo}
        assert Repository.exists?(repo) == true
      after
        File.rm_rf!(git_repo)
      end
    end

    test "rejects non-git directories" do
      temp_dir = System.tmp_dir!()
      non_git = Path.join(temp_dir, "non_git_#{:rand.uniform(10000)}")
      File.mkdir_p!(non_git)

      try do
        repo = Repository.new("test", non_git)
        repo = %{repo | path: non_git}
        assert Repository.exists?(repo) == false
      after
        File.rm_rf!(non_git)
      end
    end

    test "handles non-existent paths" do
      repo = Repository.new("test", "/non/existent/path")
      repo = %{repo | path: "/non/existent/path"}
      assert Repository.exists?(repo) == false
    end
  end

  describe "git operations" do
    test "gets branch for repository" do
      temp_dir = System.tmp_dir!()
      git_repo = Path.join(temp_dir, "branch_test_#{:rand.uniform(10000)}")
      File.mkdir_p!(git_repo)
      System.cmd("git", ["init"], cd: git_repo)
      System.cmd("git", ["config", "user.email", "test@example.com"], cd: git_repo)
      System.cmd("git", ["config", "user.name", "Test User"], cd: git_repo)

      # Create initial commit
      test_file = Path.join(git_repo, "README.md")
      File.write!(test_file, "# Test")
      System.cmd("git", ["add", "."], cd: git_repo)
      System.cmd("git", ["commit", "-m", "Initial commit"], cd: git_repo)

      try do
        repo = Repository.new("test", git_repo)
        repo = %{repo | path: git_repo}
        branch = Repository.get_branch(repo)
        assert is_binary(branch) or branch == nil
      after
        File.rm_rf!(git_repo)
      end
    end

    test "gets changes count" do
      temp_dir = System.tmp_dir!()
      dirty_repo = Path.join(temp_dir, "changes_#{:rand.uniform(10000)}")
      File.mkdir_p!(dirty_repo)
      System.cmd("git", ["init"], cd: dirty_repo)

      # Add an untracked file
      untracked_file = Path.join(dirty_repo, "untracked.txt")
      File.write!(untracked_file, "untracked content")

      try do
        repo = Repository.new("test", dirty_repo)
        repo = %{repo | path: dirty_repo}
        changes = Repository.get_changes(repo)
        assert is_integer(changes) or changes == :missing
        if is_integer(changes), do: assert(changes > 0)
      after
        File.rm_rf!(dirty_repo)
      end
    end

    test "gets last commit" do
      temp_dir = System.tmp_dir!()
      commit_repo = Path.join(temp_dir, "commit_#{:rand.uniform(10000)}")
      File.mkdir_p!(commit_repo)
      System.cmd("git", ["init"], cd: commit_repo)
      System.cmd("git", ["config", "user.email", "test@example.com"], cd: commit_repo)
      System.cmd("git", ["config", "user.name", "Test User"], cd: commit_repo)

      # Create initial commit
      test_file = Path.join(commit_repo, "README.md")
      File.write!(test_file, "# Test")
      System.cmd("git", ["add", "."], cd: commit_repo)
      System.cmd("git", ["commit", "-m", "Initial commit"], cd: commit_repo)

      try do
        repo = Repository.new("test", commit_repo)
        repo = %{repo | path: commit_repo}
        commit = Repository.get_last_commit(repo)
        assert is_binary(commit) or commit == nil
      after
        File.rm_rf!(commit_repo)
      end
    end

    test "fetches complete git info" do
      temp_dir = System.tmp_dir!()
      full_repo = Path.join(temp_dir, "full_#{:rand.uniform(10000)}")
      File.mkdir_p!(full_repo)
      System.cmd("git", ["init"], cd: full_repo)
      System.cmd("git", ["config", "user.email", "test@example.com"], cd: full_repo)
      System.cmd("git", ["config", "user.name", "Test User"], cd: full_repo)

      # Create initial commit
      test_file = Path.join(full_repo, "README.md")
      File.write!(test_file, "# Test")
      System.cmd("git", ["add", "."], cd: full_repo)
      System.cmd("git", ["commit", "-m", "Initial commit"], cd: full_repo)

      try do
        repo = Repository.new("test", full_repo)
        repo = %{repo | path: full_repo}
        updated_repo = Repository.fetch_git_info(repo)

        assert updated_repo.name == "test"
        assert is_binary(updated_repo.branch) or updated_repo.branch == nil
        assert is_integer(updated_repo.changes) or updated_repo.changes == :missing
        assert is_binary(updated_repo.last_commit) or updated_repo.last_commit == nil
      after
        File.rm_rf!(full_repo)
      end
    end

    test "handles missing repository" do
      repo = Repository.new("missing", "/non/existent")
      repo = %{repo | path: "/non/existent"}
      updated_repo = Repository.fetch_git_info(repo)

      assert updated_repo.status == :missing
      assert updated_repo.changes == :missing
    end
  end

  describe "all_repositories function" do
    test "discovers git repositories under the workspace" do
      temp_dir = System.tmp_dir!()
      workspace = Path.join(temp_dir, "all_repos_#{:rand.uniform(100_000)}")
      File.mkdir_p!(Path.join(workspace, "latex-environment"))
      System.cmd("git", ["init"], cd: Path.join(workspace, "latex-environment"))
      File.mkdir_p!(Path.join(workspace, "sotsuron-template"))
      System.cmd("git", ["init"], cd: Path.join(workspace, "sotsuron-template"))

      try do
        repos = Repository.all_repositories(workspace)
        assert is_list(repos)
        assert "." in repos
        assert "latex-environment" in repos
        assert "sotsuron-template" in repos
      after
        File.rm_rf!(workspace)
      end
    end
  end

  describe "display_name function coverage" do
    test "get_display_name through new function" do
      # Test current directory special case: display name is the workspace dir
      current_repo = Repository.new(".", "/test/path")
      assert current_repo.display_name == "path"

      # Test regular repository names
      regular_names = [
        "sotsuron-template",
        "latex-environment",
        "thesis-management-tools",
        "ai-reviewer",
        "custom-repo-name"
      ]

      for name <- regular_names do
        repo = Repository.new(name, "/base/path")
        assert repo.display_name == name
      end
    end
  end

  describe "error handling and edge cases" do
    test "git operations with invalid repositories" do
      # Test with completely invalid path
      invalid_repo = Repository.new("invalid", "/definitely/not/a/real/path")
      invalid_repo = %{invalid_repo | path: "/definitely/not/a/real/path"}

      # These should handle gracefully
      branch = Repository.get_branch(invalid_repo)
      assert branch == nil

      changes = Repository.get_changes(invalid_repo)
      assert changes == :missing

      commit = Repository.get_last_commit(invalid_repo)
      assert commit == nil

      # fetch_git_info should handle missing repositories
      updated_repo = Repository.fetch_git_info(invalid_repo)
      assert updated_repo.status == :missing
      assert updated_repo.changes == :missing
    end

    test "git operations with corrupted repositories" do
      temp_dir = System.tmp_dir!()
      corrupted_repo = Path.join(temp_dir, "corrupted_#{:rand.uniform(10000)}")
      File.mkdir_p!(corrupted_repo)

      # Create .git directory but leave it empty (corrupted)
      git_dir = Path.join(corrupted_repo, ".git")
      File.mkdir_p!(git_dir)

      try do
        repo = Repository.new("corrupted", corrupted_repo)
        repo = %{repo | path: corrupted_repo}

        # exists? should return true (directory and .git exist)
        assert Repository.exists?(repo) == true

        # But git operations should fail gracefully
        branch = Repository.get_branch(repo)
        assert branch == nil

        changes = Repository.get_changes(repo)
        assert changes == :missing

        commit = Repository.get_last_commit(repo)
        assert commit == nil

        # fetch_git_info should still work but return missing data
        updated_repo = Repository.fetch_git_info(repo)
        assert updated_repo.branch == nil
        assert updated_repo.changes == :missing
        assert updated_repo.last_commit == nil
      after
        File.rm_rf!(corrupted_repo)
      end
    end

    test "all_repositories function consistency" do
      temp_dir = System.tmp_dir!()
      workspace = Path.join(temp_dir, "consistency_#{:rand.uniform(100_000)}")

      for name <- ["texlive-ja-textlint", "latex-environment", "sotsuron-template"] do
        repo_path = Path.join(workspace, name)
        File.mkdir_p!(repo_path)
        System.cmd("git", ["init"], cd: repo_path)
      end

      try do
        repos1 = Repository.all_repositories(workspace)
        repos2 = Repository.all_repositories(workspace)

        # Should be consistent across calls
        assert repos1 == repos2

        # Should contain the workspace root plus discovered repositories
        assert "." in repos1
        assert "latex-environment" in repos1
        assert "sotsuron-template" in repos1

        # "." plus the three created repositories
        assert length(repos1) == 4
      after
        File.rm_rf!(workspace)
      end
    end
  end

  describe "comprehensive repository operations" do
    test "full repository workflow" do
      temp_dir = System.tmp_dir!()
      test_repo = Path.join(temp_dir, "workflow_#{:rand.uniform(10000)}")
      File.mkdir_p!(test_repo)
      System.cmd("git", ["init"], cd: test_repo)
      System.cmd("git", ["config", "user.email", "test@example.com"], cd: test_repo)
      System.cmd("git", ["config", "user.name", "Test User"], cd: test_repo)

      # Create and commit files
      readme = Path.join(test_repo, "README.md")
      File.write!(readme, "# Workflow Test")
      System.cmd("git", ["add", "."], cd: test_repo)
      System.cmd("git", ["commit", "-m", "Initial commit"], cd: test_repo)

      # Add uncommitted changes
      new_file = Path.join(test_repo, "new.txt")
      File.write!(new_file, "new content")

      try do
        # Test full workflow
        repo = Repository.new("workflow", test_repo)
        repo = %{repo | path: test_repo}

        # Check existence
        assert Repository.exists?(repo)

        # Fetch git info
        updated_repo = Repository.fetch_git_info(repo)

        assert updated_repo.status == :ok
        assert is_binary(updated_repo.branch)
        assert is_integer(updated_repo.changes) and updated_repo.changes > 0
        assert is_binary(updated_repo.last_commit)
      after
        File.rm_rf!(test_repo)
      end
    end

    test "concurrent operations" do
      temp_dir = System.tmp_dir!()

      # Create multiple test repositories
      repos =
        for i <- 1..5 do
          repo_path = Path.join(temp_dir, "concurrent_#{i}_#{:rand.uniform(10000)}")
          File.mkdir_p!(repo_path)
          System.cmd("git", ["init"], cd: repo_path)

          repo = Repository.new("test#{i}", repo_path)
          %{repo | path: repo_path}
        end

      try do
        # Test concurrent operations
        tasks =
          for repo <- repos do
            Task.async(fn ->
              Repository.exists?(repo) &&
                Repository.fetch_git_info(repo)
            end)
          end

        results = Task.await_many(tasks, 5000)

        for result <- results do
          assert result != false
        end
      after
        for repo <- repos do
          File.rm_rf!(repo.path)
        end
      end
    end

    test "stress testing with many repositories" do
      temp_dir = System.tmp_dir!()
      stress_base = Path.join(temp_dir, "stress_test_#{:rand.uniform(10000)}")
      File.mkdir_p!(stress_base)

      # Create many repositories for stress testing
      repo_count = 20

      repos =
        for i <- 1..repo_count do
          repo_path = Path.join(stress_base, "repo#{i}")
          File.mkdir_p!(repo_path)
          System.cmd("git", ["init"], cd: repo_path)
          System.cmd("git", ["config", "user.email", "test@example.com"], cd: repo_path)
          System.cmd("git", ["config", "user.name", "Test User"], cd: repo_path)

          # Add some files to some repositories
          if rem(i, 3) == 0 do
            File.write!(Path.join(repo_path, "README.md"), "# Repository #{i}")
            System.cmd("git", ["add", "."], cd: repo_path)
            System.cmd("git", ["commit", "-m", "Initial commit"], cd: repo_path)
          end

          # Add uncommitted changes to some
          if rem(i, 4) == 0 do
            File.write!(Path.join(repo_path, "uncommitted.txt"), "changes")
          end

          Repository.new("repo#{i}", repo_path)
          |> Map.put(:path, repo_path)
        end

      try do
        # Test batch operations
        {time_micros, results} =
          :timer.tc(fn ->
            for repo <- repos do
              Repository.fetch_git_info(repo)
            end
          end)

        # Should complete in reasonable time
        # Less than 5 seconds
        assert time_micros < 5_000_000
        assert length(results) == repo_count

        # All results should be valid
        for result <- results do
          assert is_struct(result, Repository)
          assert result.status in [:ok, :missing]
          assert is_binary(result.name)
        end

        # Test concurrent operations
        concurrent_tasks =
          for repo <- Enum.take(repos, 10) do
            Task.async(fn ->
              Repository.fetch_git_info(repo)
            end)
          end

        concurrent_results = Task.await_many(concurrent_tasks, 10_000)

        for result <- concurrent_results do
          assert is_struct(result, Repository)
        end
      after
        File.rm_rf!(stress_base)
      end
    end

    test "repository struct field validation" do
      # Test that new repositories have all expected fields
      repo = Repository.new("test", "/path")

      # Check all struct fields are present
      assert Map.has_key?(repo, :name)
      assert Map.has_key?(repo, :path)
      assert Map.has_key?(repo, :display_name)
      assert Map.has_key?(repo, :branch)
      assert Map.has_key?(repo, :changes)
      assert Map.has_key?(repo, :last_commit)
      assert Map.has_key?(repo, :issues)
      assert Map.has_key?(repo, :pull_requests)
      assert Map.has_key?(repo, :status)

      # Check initial values
      assert repo.name == "test"
      assert repo.path == "/path/test"
      assert repo.display_name == "test"
      assert repo.status == :ok

      # Check nil/unset fields
      assert repo.branch == nil
      assert repo.changes == nil
      assert repo.last_commit == nil
      assert repo.issues == nil
      assert repo.pull_requests == nil
    end
  end
end
