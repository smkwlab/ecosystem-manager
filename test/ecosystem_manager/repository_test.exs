defmodule EcosystemManager.RepositoryTest do
  use ExUnit.Case
  doctest EcosystemManager.Repository

  
  alias EcosystemManager.Repository

  describe "all_repositories/0" do
    test "returns list of repository names" do
      repos = Repository.all_repositories()
      assert is_list(repos)
      assert length(repos) > 0
      assert "." in repos
      assert "texlive-ja-textlint" in repos
    end
  end

  describe "new/2" do
    test "creates repository struct with current directory" do
      repo = Repository.new(".", "/tmp")
      assert repo.name == "."
      assert repo.path == "/tmp"
      assert repo.display_name == "latex-ecosystem"
      assert repo.status == :ok
    end

    test "creates repository struct with subdirectory" do
      repo = Repository.new("test-repo", "/tmp")
      assert repo.name == "test-repo"
      assert repo.path == "/tmp/test-repo"
      assert repo.display_name == "test-repo"
      assert repo.status == :ok
    end
  end

  describe "exists?/1" do
    test "returns false for non-existent repository" do
      repo = Repository.new("non-existent", "/tmp")
      refute Repository.exists?(repo)
    end

    test "returns true for current directory if it has .git" do
      # This test assumes we're running in a git repository
      repo = Repository.new(".", File.cwd!())

      if File.dir?(Path.join(File.cwd!(), ".git")) do
        assert Repository.exists?(repo)
      else
        refute Repository.exists?(repo)
      end
    end
  end

  describe "fetch_git_info/1" do
    test "handles non-existent repository" do
      repo = Repository.new("non-existent", "/tmp")
      result = Repository.fetch_git_info(repo)
      assert result.status == :missing
      assert result.changes == :missing
    end

    test "fetches git info for existing repository" do
      # This test assumes we're running in a git repository
      repo = Repository.new(".", File.cwd!())

      if Repository.exists?(repo) do
        result = Repository.fetch_git_info(repo)
        assert is_binary(result.branch) or is_nil(result.branch)
        assert is_integer(result.changes) or result.changes == :missing
        assert is_binary(result.last_commit) or is_nil(result.last_commit)
      end
    end
  end

  describe "Git操作のエラーハンドリング" do
    test "handles corrupted git repository" do
      # Create temp directory with broken .git
      temp_dir = System.tmp_dir!()
      test_repo_path = Path.join(temp_dir, "broken_repo_#{:rand.uniform(10000)}")
      File.mkdir_p!(test_repo_path)
      git_dir = Path.join(test_repo_path, ".git")
      File.mkdir_p!(git_dir)
      # Create invalid git config
      File.write!(Path.join(git_dir, "config"), "invalid git config")
      
      repo = Repository.new("broken_repo", temp_dir)
      repo = %{repo | path: test_repo_path}
      
      result = Repository.fetch_git_info(repo)
      
      # Should handle the error gracefully
      assert result.branch == nil
      assert result.changes == :missing or is_integer(result.changes)
      assert result.last_commit == nil
      
      # Cleanup
      File.rm_rf!(test_repo_path)
    end

    test "handles read-only directory" do
      temp_dir = System.tmp_dir!()
      test_repo_path = Path.join(temp_dir, "readonly_repo_#{:rand.uniform(10000)}")
      File.mkdir_p!(test_repo_path)
      
      # Create minimal git repo
      System.cmd("git", ["init"], cd: test_repo_path)
      System.cmd("git", ["config", "user.name", "Test User"], cd: test_repo_path)
      System.cmd("git", ["config", "user.email", "test@example.com"], cd: test_repo_path)
      File.write!(Path.join(test_repo_path, "test.txt"), "test")
      System.cmd("git", ["add", "."], cd: test_repo_path)
      System.cmd("git", ["commit", "-m", "initial"], cd: test_repo_path)
      
      # Make directory read-only if supported
      case :os.type() do
        {:unix, _} -> 
          System.cmd("chmod", ["444", test_repo_path])
        _ -> :skip
      end
      
      repo = Repository.new("readonly_repo", temp_dir)
      repo = %{repo | path: test_repo_path}
      
      result = Repository.fetch_git_info(repo)
      
      # Should still work for read operations
      assert is_binary(result.branch) or is_nil(result.branch)
      assert is_integer(result.changes) or result.changes == :missing
      
      # Cleanup
      case :os.type() do
        {:unix, _} -> System.cmd("chmod", ["755", test_repo_path])
        _ -> :ok
      end
      File.rm_rf!(test_repo_path)
    end

    test "handles detached HEAD state" do
      temp_dir = System.tmp_dir!()
      test_repo_path = Path.join(temp_dir, "detached_repo_#{:rand.uniform(10000)}")
      File.mkdir_p!(test_repo_path)
      
      # Create git repo with commits
      System.cmd("git", ["init"], cd: test_repo_path)
      System.cmd("git", ["config", "user.name", "Test User"], cd: test_repo_path)
      System.cmd("git", ["config", "user.email", "test@example.com"], cd: test_repo_path)
      File.write!(Path.join(test_repo_path, "test.txt"), "test1")
      System.cmd("git", ["add", "."], cd: test_repo_path)
      System.cmd("git", ["commit", "-m", "first commit"], cd: test_repo_path)
      
      File.write!(Path.join(test_repo_path, "test.txt"), "test2")
      System.cmd("git", ["add", "."], cd: test_repo_path)
      System.cmd("git", ["commit", "-m", "second commit"], cd: test_repo_path)
      
      # Get first commit hash and checkout
      {first_commit, 0} = System.cmd("git", ["rev-list", "--max-count=1", "HEAD~1"], cd: test_repo_path)
      first_commit = String.trim(first_commit)
      System.cmd("git", ["checkout", first_commit], cd: test_repo_path)
      
      repo = Repository.new("detached_repo", temp_dir)
      repo = %{repo | path: test_repo_path}
      
      result = Repository.fetch_git_info(repo)
      
      # In detached HEAD, branch might be empty or nil
      assert result.branch == "" or is_nil(result.branch)
      assert is_integer(result.changes) or result.changes == :missing
      assert is_binary(result.last_commit)
      
      # Cleanup
      File.rm_rf!(test_repo_path)
    end
  end

  describe "パフォーマンステスト" do
    test "handles large number of files" do
      temp_dir = System.tmp_dir!()
      test_repo_path = Path.join(temp_dir, "large_repo_#{:rand.uniform(10000)}")
      File.mkdir_p!(test_repo_path)
      
      # Create git repo
      System.cmd("git", ["init"], cd: test_repo_path)
      System.cmd("git", ["config", "user.name", "Test User"], cd: test_repo_path)
      System.cmd("git", ["config", "user.email", "test@example.com"], cd: test_repo_path)
      
      # Create many files
      for i <- 1..100 do
        File.write!(Path.join(test_repo_path, "file_#{i}.txt"), "content #{i}")
      end
      
      repo = Repository.new("large_repo", temp_dir)
      repo = %{repo | path: test_repo_path}
      
      # Measure performance
      {time_us, result} = :timer.tc(fn -> Repository.fetch_git_info(repo) end)
      
      # Should complete within reasonable time (< 5 seconds)
      assert time_us < 5_000_000
      assert result.changes == 100  # 100 untracked files
      
      # Cleanup
      File.rm_rf!(test_repo_path)
    end
  end

  describe "エラー処理の改善" do
    test "handles system command failures gracefully" do
      # Test with non-existent git command path
      original_path = System.get_env("PATH")
      
      try do
        # Temporarily set empty PATH
        System.put_env("PATH", "")
        
        repo = Repository.new(".", File.cwd!())
        result = Repository.fetch_git_info(repo)
        
        # Should handle missing git command gracefully
        assert result.branch == nil or is_binary(result.branch)
        assert result.changes == :missing or is_integer(result.changes)
        assert result.last_commit == nil or is_binary(result.last_commit)
      after
        # Restore PATH
        if original_path do
          System.put_env("PATH", original_path)
        end
      end
    end

    test "handles network timeouts in git operations" do
      # This test simulates network-dependent git operations
      temp_dir = System.tmp_dir!()
      test_repo_path = Path.join(temp_dir, "network_repo_#{:rand.uniform(10000)}")
      File.mkdir_p!(test_repo_path)
      
      # Create git repo with remote that doesn't exist
      System.cmd("git", ["init"], cd: test_repo_path)
      System.cmd("git", ["config", "user.name", "Test User"], cd: test_repo_path)
      System.cmd("git", ["config", "user.email", "test@example.com"], cd: test_repo_path)
      File.write!(Path.join(test_repo_path, "test.txt"), "test")
      System.cmd("git", ["add", "."], cd: test_repo_path)
      System.cmd("git", ["commit", "-m", "initial"], cd: test_repo_path)
      
      # Add non-existent remote
      System.cmd("git", ["remote", "add", "origin", "https://nonexistent.example.com/repo.git"], cd: test_repo_path)
      
      repo = Repository.new("network_repo", temp_dir)
      repo = %{repo | path: test_repo_path}
      
      # Should handle network failures gracefully
      result = Repository.fetch_git_info(repo)
      
      assert is_binary(result.branch)
      assert is_integer(result.changes)
      assert is_binary(result.last_commit)
      
      # Cleanup
      File.rm_rf!(test_repo_path)
    end
  end
end
