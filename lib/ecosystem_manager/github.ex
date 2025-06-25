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
end
