defmodule EcosystemManager.RepositoryConfigTest do
  use ExUnit.Case, async: false

  alias EcosystemManager.Repository

  # Create a git repository at `path` with an optional `origin` remote.
  defp init_repo(path, origin \\ nil) do
    File.mkdir_p!(path)
    System.cmd("git", ["init"], cd: path, stderr_to_stdout: true)

    if origin do
      System.cmd("git", ["remote", "add", "origin", origin], cd: path, stderr_to_stdout: true)
    end

    path
  end

  defp with_temp_workspace(fun) do
    temp_dir = System.tmp_dir!()
    workspace = Path.join(temp_dir, "ws_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(workspace)

    saved =
      for key <- [:repositories, :ecosystem_org, :workspaces, :workspace_path] do
        value = Application.get_env(:ecosystem_manager, key)
        Application.delete_env(:ecosystem_manager, key)
        {key, value}
      end

    try do
      fun.(workspace)
    after
      Enum.each(saved, fn {key, value} -> restore_env(key, value) end)
      File.rm_rf!(workspace)
    end
  end

  defp restore_env(key, nil), do: Application.delete_env(:ecosystem_manager, key)
  defp restore_env(key, value), do: Application.put_env(:ecosystem_manager, key, value)

  describe "parse_owner/1" do
    test "parses ssh, https and ssh:// GitHub URLs" do
      assert Repository.parse_owner("git@github.com:smkwlab/aldc.git") == "smkwlab"
      assert Repository.parse_owner("https://github.com/smkwlab/aldc.git") == "smkwlab"
      assert Repository.parse_owner("ssh://git@github.com/smkwlab/aldc.git") == "smkwlab"
      assert Repository.parse_owner("git@github.com:smkwlab/aldc") == "smkwlab"
    end

    test "returns nil for URLs without an owner/repo pair" do
      assert Repository.parse_owner("not-a-url") == nil
      assert Repository.parse_owner("") == nil
      assert Repository.parse_owner(nil) == nil
    end
  end

  describe "discover/1" do
    test "always includes the workspace root itself" do
      with_temp_workspace(fn ws ->
        assert "." in Repository.discover(ws)
      end)
    end

    test "includes git-repo children and excludes non-git directories" do
      with_temp_workspace(fn ws ->
        init_repo(Path.join(ws, "aldc"))
        File.mkdir_p!(Path.join(ws, "plain-dir"))

        repos = Repository.discover(ws)
        assert "aldc" in repos
        refute "plain-dir" in repos
      end)
    end

    test "excludes directories whose name ends in -test" do
      with_temp_workspace(fn ws ->
        init_repo(Path.join(ws, "aldc"))
        init_repo(Path.join(ws, "something-test"))

        repos = Repository.discover(ws)
        assert "aldc" in repos
        refute "something-test" in repos
      end)
    end

    test "filters by ecosystem org when the workspace has an origin owner" do
      with_temp_workspace(fn ws ->
        init_repo(ws, "git@github.com:smkwlab/latex-ecosystem.git")
        init_repo(Path.join(ws, "aldc"), "git@github.com:smkwlab/aldc.git")
        init_repo(Path.join(ws, "foreign"), "git@github.com:someone-else/foreign.git")

        repos = Repository.discover(ws)
        assert "aldc" in repos
        refute "foreign" in repos
      end)
    end

    test "applies no org filter when the workspace has no origin owner" do
      with_temp_workspace(fn ws ->
        # ws itself is not a git repo -> org cannot be inferred
        init_repo(Path.join(ws, "aldc"), "git@github.com:smkwlab/aldc.git")
        init_repo(Path.join(ws, "foreign"), "git@github.com:someone-else/foreign.git")

        repos = Repository.discover(ws)
        assert "aldc" in repos
        assert "foreign" in repos
      end)
    end

    test "honors an explicit :ecosystem_org config value" do
      with_temp_workspace(fn ws ->
        Application.put_env(:ecosystem_manager, :ecosystem_org, "smkwlab")
        init_repo(Path.join(ws, "aldc"), "git@github.com:smkwlab/aldc.git")
        init_repo(Path.join(ws, "foreign"), "git@github.com:someone-else/foreign.git")

        repos = Repository.discover(ws)
        assert "aldc" in repos
        refute "foreign" in repos
      end)
    end

    test "returns a sorted, deterministic list" do
      with_temp_workspace(fn ws ->
        init_repo(Path.join(ws, "wr-template"))
        init_repo(Path.join(ws, "aldc"))
        init_repo(Path.join(ws, "sotsuron-template"))

        repos = Repository.discover(ws)
        assert repos == Repository.discover(ws)
        # "." is always first, the rest are alphabetically sorted
        assert hd(repos) == "."
        assert tl(repos) == Enum.sort(tl(repos))
      end)
    end
  end

  describe "all_repositories/1" do
    test "returns explicit configuration when set" do
      with_temp_workspace(fn ws ->
        Application.put_env(:ecosystem_manager, :repositories, ["custom-a", "custom-b"])
        assert Repository.all_repositories(ws) == ["custom-a", "custom-b"]
      end)
    end

    test "falls back to discovery when repositories are not configured" do
      with_temp_workspace(fn ws ->
        init_repo(Path.join(ws, "aldc"))

        repos = Repository.all_repositories(ws)
        assert "." in repos
        assert "aldc" in repos
      end)
    end

    test "is deterministic" do
      with_temp_workspace(fn ws ->
        init_repo(Path.join(ws, "aldc"))
        assert Repository.all_repositories(ws) == Repository.all_repositories(ws)
      end)
    end

    test "honors the global repositories pin with a single configured workspace" do
      with_temp_workspace(fn ws ->
        init_repo(Path.join(ws, "aldc"))
        Application.put_env(:ecosystem_manager, :repositories, ["pinned-only"])
        Application.put_env(:ecosystem_manager, :workspaces, only: "/home/u/only")

        assert Repository.all_repositories(ws) == ["pinned-only"]
      end)
    end

    test "ignores the global repositories pin when multiple workspaces are configured" do
      with_temp_workspace(fn ws ->
        init_repo(Path.join(ws, "aldc"))
        Application.put_env(:ecosystem_manager, :repositories, ["pinned-only"])
        Application.put_env(:ecosystem_manager, :workspaces, a: "/home/u/a", b: "/home/u/b")

        repos = Repository.all_repositories(ws)
        refute "pinned-only" in repos
        assert "aldc" in repos
      end)
    end
  end

  describe "get_configured_repositories/0" do
    test "returns config value (nil or list)" do
      result = Repository.get_configured_repositories()
      assert is_nil(result) or is_list(result)
    end
  end
end
