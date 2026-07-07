defmodule EcosystemManager.WorkspaceTest do
  use ExUnit.Case, async: false

  alias EcosystemManager.Workspace

  setup do
    original_workspaces = Application.get_env(:ecosystem_manager, :workspaces)
    original_workspace_path = Application.get_env(:ecosystem_manager, :workspace_path)
    Application.delete_env(:ecosystem_manager, :workspaces)
    Application.delete_env(:ecosystem_manager, :workspace_path)

    on_exit(fn ->
      restore_env(:workspaces, original_workspaces)
      restore_env(:workspace_path, original_workspace_path)
    end)
  end

  defp restore_env(key, nil), do: Application.delete_env(:ecosystem_manager, key)
  defp restore_env(key, value), do: Application.put_env(:ecosystem_manager, key, value)

  describe "list/0" do
    test "returns [] when nothing is configured" do
      assert Workspace.list() == []
    end

    test "normalizes the :workspaces keyword list, expanding ~" do
      Application.put_env(:ecosystem_manager, :workspaces,
        latex: "/home/u/latex-ecosystem",
        dns: "~/dns/ecosystem"
      )

      assert [latex, dns] = Workspace.list()
      assert latex.name == "latex"
      assert latex.path == "/home/u/latex-ecosystem"
      assert dns.name == "dns"
      assert dns.path == Path.expand("~/dns/ecosystem")
    end

    test "falls back to legacy workspace_path as a single named workspace" do
      Application.put_env(:ecosystem_manager, :workspace_path, "/home/u/latex-ecosystem")

      assert [ws] = Workspace.list()
      assert ws.name == "latex-ecosystem"
      assert ws.path == "/home/u/latex-ecosystem"
    end

    test "prefers :workspaces over legacy :workspace_path" do
      Application.put_env(:ecosystem_manager, :workspace_path, "/home/u/legacy")
      Application.put_env(:ecosystem_manager, :workspaces, only: "/home/u/only")

      assert [ws] = Workspace.list()
      assert ws.name == "only"
      assert ws.path == "/home/u/only"
    end
  end

  describe "resolve/2 by name" do
    setup do
      Application.put_env(:ecosystem_manager, :workspaces,
        latex: "/home/u/latex-ecosystem",
        dns: "/home/u/dns/ecosystem"
      )

      :ok
    end

    test "selects a workspace by explicit name regardless of cwd" do
      assert {:ok, ws} = Workspace.resolve("dns", "/somewhere/else")
      assert ws.name == "dns"
    end

    test "returns an error listing registered names for an unknown name" do
      assert {:error, message} = Workspace.resolve("nope", "/tmp")
      assert message =~ "Unknown workspace: nope"
      assert message =~ "latex"
      assert message =~ "dns"
    end
  end

  describe "valid_name?/1" do
    test "accepts identifier-like names" do
      assert Workspace.valid_name?("latex")
      assert Workspace.valid_name?("dns")
      assert Workspace.valid_name?("a-b_c1")
      assert Workspace.valid_name?(String.duplicate("a", 64))
    end

    test "rejects empty, whitespace, path separators and overly long names" do
      refute Workspace.valid_name?("")
      refute Workspace.valid_name?("my workspace")
      refute Workspace.valid_name?("a/b")
      refute Workspace.valid_name?(String.duplicate("a", 65))
      refute Workspace.valid_name?(nil)
    end
  end

  describe "resolve/2 by cwd" do
    setup do
      Application.put_env(:ecosystem_manager, :workspaces,
        latex: "/home/u/latex-ecosystem",
        dns: "/home/u/dns/ecosystem"
      )

      :ok
    end

    test "selects the workspace that contains cwd" do
      assert {:ok, ws} = Workspace.resolve(nil, "/home/u/latex-ecosystem/aldc")
      assert ws.name == "latex"
    end

    test "normalizes cwd (trailing slash / relative segments) before matching" do
      assert {:ok, %{name: "latex"}} = Workspace.resolve(nil, "/home/u/latex-ecosystem/")
      assert {:ok, %{name: "latex"}} = Workspace.resolve(nil, "/home/u/latex-ecosystem/sub/..")
    end

    test "matches when cwd equals the workspace path" do
      assert {:ok, ws} = Workspace.resolve(nil, "/home/u/dns/ecosystem")
      assert ws.name == "dns"
    end

    test "returns :none when cwd is outside every workspace and several exist" do
      assert Workspace.resolve(nil, "/home/u/unrelated") == :none
    end

    test "does not match a sibling directory sharing a path prefix" do
      # /home/u/latex-ecosystem must not match /home/u/latex-ecosystem-extra
      assert Workspace.resolve(nil, "/home/u/latex-ecosystem-extra") == :none
    end
  end

  describe "resolve/2 deepest match" do
    test "prefers the most specific (deepest) containing workspace" do
      Application.put_env(:ecosystem_manager, :workspaces,
        outer: "/home/u/prj",
        inner: "/home/u/prj/latex-ecosystem"
      )

      assert {:ok, ws} = Workspace.resolve(nil, "/home/u/prj/latex-ecosystem/aldc")
      assert ws.name == "inner"
    end
  end

  describe "resolve/2 single workspace" do
    test "uses the only workspace even when cwd is outside it" do
      Application.put_env(:ecosystem_manager, :workspaces, latex: "/home/u/latex-ecosystem")

      assert {:ok, ws} = Workspace.resolve(nil, "/somewhere/else")
      assert ws.name == "latex"
    end
  end

  describe "containing/1" do
    test "returns the deepest workspace containing cwd" do
      Application.put_env(:ecosystem_manager, :workspaces,
        outer: "/home/u/prj",
        inner: "/home/u/prj/latex-ecosystem"
      )

      assert %Workspace{name: "inner"} = Workspace.containing("/home/u/prj/latex-ecosystem/aldc")
    end

    test "returns nil outside every workspace, with no single-workspace fallback" do
      Application.put_env(:ecosystem_manager, :workspaces, latex: "/home/u/latex-ecosystem")

      assert Workspace.containing("/home/u/dns/ecosystem") == nil
    end
  end
end
