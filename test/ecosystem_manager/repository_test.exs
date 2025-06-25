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
end
