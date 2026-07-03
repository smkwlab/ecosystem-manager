defmodule EcosystemManager.RepositoryConfigTest do
  use ExUnit.Case

  alias EcosystemManager.Repository

  describe "repository configuration" do
    test "default_repositories/0 returns the built-in list" do
      defaults = Repository.default_repositories()
      assert is_list(defaults)
      assert "." in defaults
      assert "texlive-ja-textlint" in defaults
      assert length(defaults) > 5
    end

    test "default_repositories/0 includes all ecosystem template repositories" do
      defaults = Repository.default_repositories()

      for template <- [
            "sotsuron-template",
            "latex-template",
            "sotsuron-report-template",
            "wr-template",
            "ise-report-template",
            "poster-template"
          ] do
        assert template in defaults
      end
    end

    test "get_configured_repositories/0 returns config value" do
      result = Repository.get_configured_repositories()
      # Should be either nil or a list
      assert is_nil(result) or is_list(result)
    end

    test "all_repositories/0 falls back to defaults when no config exists" do
      repos = Repository.all_repositories()
      assert is_list(repos)
      assert length(repos) > 0
    end

    test "all_repositories/0 is deterministic" do
      repos1 = Repository.all_repositories()
      repos2 = Repository.all_repositories()
      assert repos1 == repos2
    end

    test "default_repositories/0 is stable" do
      defaults1 = Repository.default_repositories()
      defaults2 = Repository.default_repositories()

      assert defaults1 == defaults2
      assert is_list(defaults1)
      assert "." in defaults1
      assert length(defaults1) > 0
    end
  end
end
