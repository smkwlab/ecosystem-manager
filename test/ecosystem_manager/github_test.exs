defmodule EcosystemManager.GitHubTest do
  use ExUnit.Case, async: false

  alias EcosystemManager.GitHub

  # Create a git repository at `path` whose origin is `origin`.
  defp init_repo(path, origin) do
    File.mkdir_p!(path)
    System.cmd("git", ["init"], cd: path, stderr_to_stdout: true)
    System.cmd("git", ["remote", "add", "origin", origin], cd: path, stderr_to_stdout: true)
    path
  end

  defp with_repo(origin, fun) do
    path = Path.join(System.tmp_dir!(), "gh_#{:rand.uniform(1_000_000)}")
    init_repo(path, origin)

    try do
      fun.(%{path: path})
    after
      File.rm_rf!(path)
    end
  end

  describe "get_github_remote/1" do
    test "parses the SSH form" do
      with_repo("git@github.com:smkwlab/aldc.git", fn repo ->
        assert GitHub.get_github_remote(repo) == {:ok, {"smkwlab", "aldc"}}
      end)
    end

    test "parses the HTTPS form" do
      with_repo("https://github.com/smkwlab/aldc.git", fn repo ->
        assert GitHub.get_github_remote(repo) == {:ok, {"smkwlab", "aldc"}}
      end)
    end

    test "parses the ssh:// form" do
      with_repo("ssh://git@github.com/smkwlab/aldc.git", fn repo ->
        assert GitHub.get_github_remote(repo) == {:ok, {"smkwlab", "aldc"}}
      end)
    end

    test "keeps a name that starts with a dot" do
      # smkwlab/.github holds the org's reusable workflows, so losing its
      # issues and PRs is not a corner case.
      with_repo("git@github.com:smkwlab/.github.git", fn repo ->
        assert GitHub.get_github_remote(repo) == {:ok, {"smkwlab", ".github"}}
      end)
    end

    test "keeps a dotted name over HTTPS too" do
      with_repo("https://github.com/smkwlab/.github.git", fn repo ->
        assert GitHub.get_github_remote(repo) == {:ok, {"smkwlab", ".github"}}
      end)
    end

    test "strips only the trailing .git, not every occurrence" do
      with_repo("git@github.com:smkwlab/dot.github.git", fn repo ->
        assert GitHub.get_github_remote(repo) == {:ok, {"smkwlab", "dot.github"}}
      end)
    end

    test "handles a remote with no .git suffix" do
      with_repo("git@github.com:smkwlab/.github", fn repo ->
        assert GitHub.get_github_remote(repo) == {:ok, {"smkwlab", ".github"}}
      end)
    end

    test "returns :error for a non-GitHub remote" do
      with_repo("git@gitlab.com:smkwlab/aldc.git", fn repo ->
        assert GitHub.get_github_remote(repo) == :error
      end)
    end
  end
end
