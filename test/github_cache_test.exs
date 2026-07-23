defmodule EcosystemManager.GitHubCacheTest do
  # async: false — the mock gh-CLI invocation counter lives in :persistent_term
  # and is shared process-wide, so this module must not run alongside other
  # tests that exercise the mock.
  use ExUnit.Case, async: false

  alias EcosystemManager.GitHub

  setup do
    System.put_env("MOCK_GH_CLI", "true")
    GitHub.reset_mock_gh_call_count()

    cache_dir = Path.join(System.tmp_dir!(), "em-cache-#{System.unique_integer([:positive])}")

    on_exit(fn ->
      System.delete_env("MOCK_GH_CLI")
      File.rm_rf!(cache_dir)
    end)

    {:ok, cache_dir: cache_dir}
  end

  describe "caching enabled (use_cache: true)" do
    test "a cache hit does not shell out to gh", %{cache_dir: cache_dir} do
      opts = [use_cache: true, cache_dir: cache_dir]

      # First call: cache miss -> gh CLI is invoked once and the result stored.
      first = GitHub.get_issues("owner", "repo", opts)
      assert GitHub.mock_gh_call_count() == 1
      assert first.total == 3

      # Second call: cache hit -> gh CLI must NOT be invoked again.
      second = GitHub.get_issues("owner", "repo", opts)
      assert GitHub.mock_gh_call_count() == 1
      assert second == first
    end

    test "issues and pull requests use independent cache entries", %{cache_dir: cache_dir} do
      opts = [use_cache: true, cache_dir: cache_dir]

      GitHub.get_issues("owner", "repo", opts)
      GitHub.get_pull_requests("owner", "repo", opts)
      # Distinct keys -> two gh calls populate two entries.
      assert GitHub.mock_gh_call_count() == 2

      # Both are now served from cache.
      GitHub.get_issues("owner", "repo", opts)
      GitHub.get_pull_requests("owner", "repo", opts)
      assert GitHub.mock_gh_call_count() == 2
    end

    test "cache entries are per repository", %{cache_dir: cache_dir} do
      opts = [use_cache: true, cache_dir: cache_dir]

      GitHub.get_issues("owner", "repo-a", opts)
      GitHub.get_issues("owner", "repo-b", opts)
      # Different repos -> different keys -> both miss.
      assert GitHub.mock_gh_call_count() == 2
    end

    test "an expired entry is refetched", %{cache_dir: cache_dir} do
      # ttl: 0 makes every stored entry already expired, so the cache never hits.
      opts = [use_cache: true, cache_dir: cache_dir, cache_ttl: 0]

      GitHub.get_issues("owner", "repo", opts)
      GitHub.get_issues("owner", "repo", opts)
      assert GitHub.mock_gh_call_count() == 2
    end

    test "the cache file is written under the github category", %{cache_dir: cache_dir} do
      opts = [use_cache: true, cache_dir: cache_dir]
      GitHub.get_issues("owner", "repo", opts)

      github_dir = Path.join(cache_dir, "github")
      assert File.dir?(github_dir)
      assert length(File.ls!(github_dir)) == 1
    end
  end

  describe "--no-cache (use_cache: false)" do
    test "always invokes gh and never reads the cache", %{cache_dir: cache_dir} do
      # Pre-populate the cache with an enabled call.
      GitHub.get_issues("owner", "repo", use_cache: true, cache_dir: cache_dir)
      assert GitHub.mock_gh_call_count() == 1

      # With caching off, the stored entry must be ignored and gh re-invoked.
      GitHub.get_issues("owner", "repo", use_cache: false, cache_dir: cache_dir)
      GitHub.get_issues("owner", "repo", use_cache: false, cache_dir: cache_dir)
      assert GitHub.mock_gh_call_count() == 3
    end

    test "does not write a cache entry", %{cache_dir: cache_dir} do
      GitHub.get_issues("owner", "repo", use_cache: false, cache_dir: cache_dir)
      # Nothing persisted when caching is disabled.
      refute File.dir?(Path.join(cache_dir, "github"))
    end

    test "caching is off by default", %{cache_dir: cache_dir} do
      # No :use_cache option at all behaves like --no-cache.
      GitHub.get_issues("owner", "repo", cache_dir: cache_dir)
      GitHub.get_issues("owner", "repo", cache_dir: cache_dir)
      assert GitHub.mock_gh_call_count() == 2
      refute File.dir?(Path.join(cache_dir, "github"))
    end
  end
end
