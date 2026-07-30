defmodule EcosystemManager.GitHub do
  @moduledoc """
  GitHub API operations for repository information.

  GitHub data is fetched through the `gh` CLI (`gh issue/pr list --json`). The
  per-repository results are cached with `ToolKit.Cache` under
  `~/.cache/ecosystem-manager/github/` so repeated runs skip the CLI while the
  entries are fresh.

  Caching is opt-in per call via the `:use_cache` option (the CLI turns it on
  from the `enable_cache` config unless `--no-cache` is given). The `--fast`
  flag is a separate concern: it skips GitHub access entirely, so no cache is
  read or written in that mode.
  """

  require Logger

  alias EcosystemManager.Config
  alias ToolKit.Cache

  # Cache subdirectory (category) under the cache directory.
  @cache_category "github"

  @doc """
  Get issues and pull requests for a repository.

  Options:

    * `:use_cache` — read/write the per-repository cache (default `false`)
    * `:cache_dir` — override the cache directory (defaults to `Config.cache_dir/0`)
    * `:cache_ttl` — override the cache TTL in seconds (defaults to
      `Config.cache_ttl_seconds/0`)
  """
  def fetch_github_info(repo, opts \\ []) do
    if EcosystemManager.Repository.exists?(repo) do
      case get_github_remote(repo) do
        {:ok, {owner, repo_name}} ->
          fetch_remote_info(repo, owner, repo_name, opts)

        :error ->
          default_github_info(repo)
      end
    else
      default_github_info(repo)
    end
  end

  # Private helper to reduce nesting
  defp fetch_remote_info(repo, owner, repo_name, opts) do
    issues_task = Task.async(fn -> get_issues(owner, repo_name, opts) end)
    prs_task = Task.async(fn -> get_pull_requests(owner, repo_name, opts) end)

    issues = Task.await(issues_task, 10_000)
    prs = Task.await(prs_task, 10_000)

    %{repo | issues: issues, pull_requests: prs}
  end

  # Private helper for default GitHub info
  defp default_github_info(repo) do
    %{
      repo
      | issues: %{total: 0, bugs: 0, enhancements: 0, urgent: 0},
        pull_requests: %{total: 0, drafts: 0, needs_review: 0}
    }
  end

  @doc "Get GitHub repository owner and name from git remote"
  def get_github_remote(%{path: path}) do
    case System.cmd("git", ["remote", "get-url", "origin"], cd: path, stderr_to_stdout: true) do
      {url, 0} ->
        url = String.trim(url)
        parse_github_url(url)

      _ ->
        :error
    end
  end

  @doc "Get issues for a repository"
  def get_issues(owner, repo, opts \\ []) do
    case cached_gh_call(
           cache_key(owner, repo, "issues"),
           [
             "issue",
             "list",
             "--repo",
             "#{owner}/#{repo}",
             "--state",
             "open",
             "--json",
             "number,title,labels"
           ],
           opts
         ) do
      {:ok, issues} ->
        total = length(issues)
        bugs = count_by_labels(issues, ~w[bug error critical regression])
        enhancements = count_by_labels(issues, ~w[enhancement feature improvement request])
        urgent = count_by_labels(issues, ~w[critical urgent high])

        %{total: total, bugs: bugs, enhancements: enhancements, urgent: urgent}

      {:error, _} ->
        %{total: 0, bugs: 0, enhancements: 0, urgent: 0}
    end
  end

  @doc "Get pull requests for a repository"
  def get_pull_requests(owner, repo, opts \\ []) do
    case cached_gh_call(
           cache_key(owner, repo, "prs"),
           [
             "pr",
             "list",
             "--repo",
             "#{owner}/#{repo}",
             "--json",
             "number,title,isDraft,reviewDecision"
           ],
           opts
         ) do
      {:ok, prs} ->
        total = length(prs)
        drafts = Enum.count(prs, & &1["isDraft"])

        needs_review =
          Enum.count(prs, fn pr ->
            not pr["isDraft"] and pr["reviewDecision"] in [nil, "REVIEW_REQUIRED"]
          end)

        %{total: total, drafts: drafts, needs_review: needs_review}

      {:error, _} ->
        %{total: 0, drafts: 0, needs_review: 0}
    end
  end

  # Private functions

  # Look the result up in the cache first (when caching is enabled for this
  # call); on a miss, run the gh CLI and store a successful result. `--no-cache`
  # / disabled cache is expressed as `use_cache?/1` returning false, in which
  # case the CLI is always run and nothing is written.
  defp cached_gh_call(key, args, opts) do
    if use_cache?(opts) do
      case Cache.get(key, cache_opts(opts)) do
        {:ok, data} -> {:ok, data}
        {:error, _reason} -> fetch_and_cache(key, args, opts)
      end
    else
      gh_api_call(args)
    end
  end

  defp fetch_and_cache(key, args, opts) do
    case gh_api_call(args) do
      {:ok, data} = ok ->
        _ = Cache.put(key, data, cache_opts(opts))
        ok

      other ->
        other
    end
  end

  defp use_cache?(opts), do: Keyword.get(opts, :use_cache, false)

  defp cache_opts(opts) do
    [
      cache_dir: Path.expand(Keyword.get(opts, :cache_dir, Config.cache_dir())),
      category: @cache_category,
      ttl: Keyword.get(opts, :cache_ttl, Config.cache_ttl_seconds())
    ]
  end

  # gh issue/pr list are distinct calls for the same repo, so the kind keeps
  # their entries apart. ToolKit.Cache sanitizes the key into a single flat
  # filename (its moduledoc guarantees "owner/repo"-style names map to one
  # file), so the "/" and ":" here are never treated as path separators.
  defp cache_key(owner, repo, kind), do: "#{owner}/#{repo}:#{kind}"

  defp gh_api_call(args) do
    # Check for mock mode in test environment
    if System.get_env("MOCK_GH_CLI") == "true" do
      _ = bump_mock_call_count()
      mock_gh_response(args)
    else
      real_gh_api_call(args)
    end
  end

  # The mock gh-CLI invocation counter is test-only: production builds get a
  # no-op bump and never touch persistent_term at runtime. persistent_term is
  # acceptable for the counter because MOCK_GH_CLI is set only by the suite, so
  # it is updated just a handful of times per test (not a hot path). The key
  # and every accessor live in this single block so the attribute is defined
  # and referenced together (no cross-block compile-order coupling).
  if Mix.env() == :test do
    @mock_counter_key {__MODULE__, :mock_gh_call_count}

    defp bump_mock_call_count,
      do: :persistent_term.put(@mock_counter_key, :persistent_term.get(@mock_counter_key, 0) + 1)

    @doc false
    def reset_mock_gh_call_count, do: :persistent_term.put(@mock_counter_key, 0)

    @doc false
    def mock_gh_call_count, do: :persistent_term.get(@mock_counter_key, 0)
  else
    defp bump_mock_call_count, do: :ok
  end

  defp real_gh_api_call(args) do
    case System.cmd("gh", args, stderr_to_stdout: true) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, data} -> {:ok, data}
          {:error, _} -> {:error, :invalid_json}
        end

      {error, _} ->
        # Log at debug level to avoid noise in normal operation
        Logger.debug("GitHub CLI command failed: #{inspect(args)}, error: #{error}")
        {:error, :gh_command_failed}
    end
  end

  # Mock gh CLI responses for testing
  defp mock_gh_response(args) do
    cond do
      # Mock invalid JSON response - check this first
      System.get_env("MOCK_INVALID_JSON") == "true" ->
        # Return error to test error handling
        {:error, :invalid_json}

      # Mock issue list command
      "issue" in args and "list" in args ->
        {:ok,
         [
           %{
             "number" => 1,
             "title" => "Bug: Authentication fails",
             "labels" => [%{"name" => "bug"}, %{"name" => "critical"}]
           },
           %{
             "number" => 2,
             "title" => "Feature: Add dark mode",
             "labels" => [%{"name" => "enhancement"}]
           },
           %{
             "number" => 3,
             "title" => "Urgent: Security vulnerability",
             "labels" => [%{"name" => "urgent"}, %{"name" => "security"}]
           }
         ]}

      # Mock PR list command
      "pr" in args and "list" in args ->
        {:ok,
         [
           %{
             "number" => 10,
             "title" => "Fix authentication bug",
             "isDraft" => false,
             "reviewDecision" => "REVIEW_REQUIRED"
           },
           %{
             "number" => 11,
             "title" => "WIP: New feature",
             "isDraft" => true,
             "reviewDecision" => nil
           },
           %{
             "number" => 12,
             "title" => "Update documentation",
             "isDraft" => false,
             "reviewDecision" => "APPROVED"
           }
         ]}

      true ->
        {:error, :gh_command_failed}
    end
  end

  defp parse_github_url(url) do
    if String.contains?(url, "github.com") do
      # Extract owner/repo from various GitHub URL formats. The repository name
      # may contain dots and may even start with one (smkwlab/.github), so only
      # a path separator ends it -- the ".git" suffix is stripped afterwards.
      regex = ~r/github\.com[\/:]([^\/]+)\/([^\/\s]+)/

      case Regex.run(regex, url) do
        # replace_suffix, not replace: a name like dot.github would otherwise
        # lose its inner ".git" as well.
        [_, owner, repo] -> {:ok, {owner, String.replace_suffix(repo, ".git", "")}}
        _ -> :error
      end
    else
      :error
    end
  end

  defp count_by_labels(issues, target_labels) do
    issues
    |> Enum.count(fn issue ->
      labels = issue["labels"] || []

      Enum.any?(labels, fn label ->
        label_name = String.downcase(label["name"] || "")
        Enum.any?(target_labels, &String.contains?(label_name, &1))
      end)
    end)
  end

  # Test helpers - compiled only in the :test environment, so they never
  # exist in production builds
  if Mix.env() == :test do
    @doc false
    def test_count_by_labels(issues, target_labels), do: count_by_labels(issues, target_labels)

    @doc false
    def test_process_issues_success(issues) do
      total = length(issues)
      bugs = count_by_labels(issues, ~w[bug error critical regression])
      enhancements = count_by_labels(issues, ~w[enhancement feature improvement request])
      urgent = count_by_labels(issues, ~w[critical urgent high])
      %{total: total, bugs: bugs, enhancements: enhancements, urgent: urgent}
    end

    @doc false
    def test_process_prs_success(prs) do
      total = length(prs)
      drafts = Enum.count(prs, & &1["isDraft"])

      needs_review =
        Enum.count(prs, fn pr ->
          not pr["isDraft"] and pr["reviewDecision"] in [nil, "REVIEW_REQUIRED"]
        end)

      %{total: total, drafts: drafts, needs_review: needs_review}
    end
  end
end
