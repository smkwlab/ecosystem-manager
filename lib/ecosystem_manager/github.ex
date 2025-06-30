defmodule EcosystemManager.GitHub do
  @moduledoc """
  GitHub API operations for repository information.
  """

  require Logger

  @doc "Get issues and pull requests for a repository"
  def fetch_github_info(repo) do
    if EcosystemManager.Repository.exists?(repo) do
      case get_github_remote(repo) do
        {:ok, {owner, repo_name}} ->
          fetch_remote_info(repo, owner, repo_name)

        :error ->
          default_github_info(repo)
      end
    else
      default_github_info(repo)
    end
  end

  # Private helper to reduce nesting
  defp fetch_remote_info(repo, owner, repo_name) do
    issues_task = Task.async(fn -> get_issues(owner, repo_name) end)
    prs_task = Task.async(fn -> get_pull_requests(owner, repo_name) end)

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
  def get_issues(owner, repo) do
    case gh_api_call([
           "issue",
           "list",
           "--repo",
           "#{owner}/#{repo}",
           "--state",
           "open",
           "--json",
           "number,title,labels"
         ]) do
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
  def get_pull_requests(owner, repo) do
    case gh_api_call([
           "pr",
           "list",
           "--repo",
           "#{owner}/#{repo}",
           "--json",
           "number,title,isDraft,reviewDecision"
         ]) do
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

  defp gh_api_call(args) do
    # In test environment, check for mock mode
    if Application.get_env(:ecosystem_manager, :env) == :test and System.get_env("MOCK_GH_CLI") == "true" do
      mock_gh_response(args)
    else
      real_gh_api_call(args)
    end
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
      # Extract owner/repo from various GitHub URL formats
      regex = ~r/github\.com[\/:]([^\/]+)\/([^\/\s\.]+)/

      case Regex.run(regex, url) do
        [_, owner, repo] -> {:ok, {owner, String.replace(repo, ".git", "")}}
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

  # Test helpers - exposed only for testing
  if Mix.env() == :test do
    def test_count_by_labels(issues, target_labels), do: count_by_labels(issues, target_labels)

    def test_process_issues_success(issues) do
      total = length(issues)
      bugs = count_by_labels(issues, ~w[bug error critical regression])
      enhancements = count_by_labels(issues, ~w[enhancement feature improvement request])
      urgent = count_by_labels(issues, ~w[critical urgent high])
      %{total: total, bugs: bugs, enhancements: enhancements, urgent: urgent}
    end

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
