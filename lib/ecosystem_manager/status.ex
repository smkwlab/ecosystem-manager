defmodule EcosystemManager.Status do
  @moduledoc """
  Status command implementation with parallel processing.
  """

  alias EcosystemManager.Config
  alias EcosystemManager.GitHub
  alias EcosystemManager.Repository

  @doc "Get status of all repositories in parallel"
  def get_all_status(base_path, opts \\ []) do
    max_concurrency = Keyword.get(opts, :max_concurrency, Config.default_concurrency())
    include_github = Keyword.get(opts, :include_github, Config.default_include_github())
    github_opts = github_opts(opts)

    Repository.all_repositories(base_path)
    |> Enum.map(&Repository.new(&1, base_path))
    |> Task.async_stream(&fetch_repository_info(&1, include_github, github_opts),
      max_concurrency: max_concurrency,
      timeout: Config.github_timeout()
    )
    |> Enum.map(fn
      {:ok, repo} ->
        repo

      {:error, reason} ->
        IO.puts("Error fetching repository info: #{inspect(reason)}")
        nil
    end)
    |> Enum.filter(& &1)
  end

  @doc "Get status of a specific repository"
  def get_repository_status(repo_name, base_path, opts \\ []) do
    include_github = Keyword.get(opts, :include_github, Config.default_include_github())

    repo_name
    |> Repository.new(base_path)
    |> fetch_repository_info(include_github, github_opts(opts))
  end

  # GitHub-specific options forwarded to EcosystemManager.GitHub. Caching is
  # opt-in and off unless the caller enabled it (the CLI derives this from the
  # enable_cache config and --no-cache).
  defp github_opts(opts) do
    [use_cache: Keyword.get(opts, :use_cache, false)]
  end

  @doc "Format status for display"
  def format_status(repos, opts \\ []) do
    format = Keyword.get(opts, :format, Config.default_format())
    filters = Keyword.get(opts, :filters, [])
    time_sort = Keyword.get(opts, :time_sort, false)

    repos
    |> apply_filters(filters)
    |> maybe_sort_by_time(time_sort)
    |> format_output(format)
  end

  @doc "Sort repositories by last commit time (newest first)"
  def sort_repositories_by_time(repos) do
    repos
    |> Enum.sort_by(
      fn repo ->
        # repos without commits get 0 (go to end)
        repo.last_commit_timestamp || 0
      end,
      # descending order (newest first)
      :desc
    )
  end

  # Sort by time if time_sort option is enabled
  defp maybe_sort_by_time(repos, true), do: sort_repositories_by_time(repos)
  defp maybe_sort_by_time(repos, false), do: repos

  # Private functions

  defp fetch_repository_info(repo, include_github, github_opts) do
    # First get git information (fast)
    repo = Repository.fetch_git_info(repo)

    # Then get GitHub information if requested (slower)
    if include_github and repo.status != :missing do
      GitHub.fetch_github_info(repo, github_opts)
    else
      %{
        repo
        | issues: %{total: 0, bugs: 0, enhancements: 0, urgent: 0},
          pull_requests: %{total: 0, drafts: 0, needs_review: 0}
      }
    end
  end

  defp apply_filters(repos, []), do: repos

  defp apply_filters(repos, filters) do
    Enum.filter(repos, fn repo ->
      Enum.all?(filters, &apply_filter(repo, &1))
    end)
  end

  defp apply_filter(repo, {:urgent_issues_only, true}) do
    repo.issues.urgent > 0
  end

  defp apply_filter(repo, {:with_prs_only, true}) do
    repo.pull_requests.total > 0
  end

  defp apply_filter(repo, {:needs_review_only, true}) do
    repo.pull_requests.needs_review > 0
  end

  defp apply_filter(_repo, _filter), do: true

  defp format_output(repos, :compact) do
    header = format_header(:compact)
    separator = format_separator(:compact)

    rows = Enum.map(repos, &format_repository_row(&1, :compact))

    [header, separator | rows]
    |> Enum.join("\n")
  end

  defp format_output(repos, :long) do
    # long mode never truncates, so column widths are variable. Compute each
    # column's max display width across the header, separator and data rows,
    # then pad every cell to that width instead of using tab separators.
    all_rows = [long_header_cells(), long_separator_cells() | Enum.map(repos, &long_row_cells/1)]
    widths = column_widths(all_rows)

    Enum.map_join(all_rows, "\n", &format_long_row(&1, widths))
  end

  defp long_header_cells,
    do: ["Repository", "Branch", "Changes", "Last Commit", "PRs", "Issues"]

  # Derive the dash separators from the header labels so they can never drift
  # out of sync when a header label is renamed.
  defp long_separator_cells,
    do: Enum.map(long_header_cells(), &String.duplicate("-", String.length(&1)))

  defp long_row_cells(repo) do
    [
      repo.display_name || "",
      repo.branch || "unknown",
      format_changes(repo.changes),
      repo.last_commit || "unknown",
      format_pr_info(repo.pull_requests, :long),
      format_issue_info(repo.issues, :long)
    ]
  end

  # Per-column max display width across every row: turn each row into its cell
  # lengths, then transpose and take the column maxima. Returns [] for no rows
  # (never nil). String.length is enough for the ASCII-centric values shown
  # here; revisit for CJK/emoji content.
  defp column_widths(rows) do
    rows
    |> Enum.map(fn cells -> Enum.map(cells, &String.length/1) end)
    |> Enum.zip_with(&Enum.max/1)
  end

  # Pad each column to its width with a single-space separator; the trailing
  # padding of the last column is trimmed to avoid dangling whitespace. The
  # cell/width counts must match — every row producer emits the same fixed
  # column set — so the guard fails loudly rather than letting Enum.zip/2
  # silently drop columns if that invariant is ever broken.
  defp format_long_row(cells, widths) when length(cells) == length(widths) do
    cells
    |> Enum.zip(widths)
    |> Enum.map_join(" ", fn {cell, width} -> String.pad_trailing(cell, width) end)
    |> String.trim_trailing()
  end

  defp format_header(:compact) do
    sprintf(
      "~-26s ~-27s ~-8s ~-22s ~-8s ~-8s",
      ["Repository", "Branch", "Changes", "Last Commit", "PRs", "Issues"]
    )
  end

  defp format_separator(:compact) do
    sprintf(
      "~-26s ~-27s ~-8s ~-22s ~-8s ~-8s",
      ["----------", "------", "-------", "-----------", "---", "------"]
    )
  end

  defp format_repository_row(repo, :compact) do
    display_name = truncate_string(repo.display_name, 26)
    branch = truncate_string(repo.branch || "unknown", 27)
    changes = format_changes(repo.changes)
    last_commit = truncate_string(repo.last_commit || "unknown", 22)
    pr_info = format_pr_info(repo.pull_requests, :compact)
    issue_info = format_issue_info(repo.issues, :compact)

    sprintf(
      "~-26s ~-27s ~-8s ~-22s ~-8s ~-8s",
      [display_name, branch, changes, last_commit, pr_info, issue_info]
    )
  end

  defp format_changes(:missing), do: "missing"
  defp format_changes(0), do: "clean"
  defp format_changes(n), do: "#{n}"

  defp format_pr_info(nil, _format), do: "0"

  defp format_pr_info(%{total: total, drafts: drafts, needs_review: needs_review}, :compact) do
    cond do
      needs_review > 0 -> "#{total}(r)"
      drafts > 0 -> "#{total}(d)"
      true -> "#{total}"
    end
  end

  defp format_pr_info(%{total: total, drafts: drafts, needs_review: needs_review}, :long) do
    "#{total} (#{drafts}d, #{needs_review}r)"
  end

  defp format_issue_info(nil, _format), do: "0"

  defp format_issue_info(%{total: total, urgent: urgent}, :compact) do
    if urgent > 0 do
      "#{total}(!)"
    else
      "#{total}"
    end
  end

  defp format_issue_info(
         %{total: total, bugs: bugs, enhancements: enhancements, urgent: urgent},
         :long
       ) do
    "#{total} (#{bugs}b, #{enhancements}e, #{urgent}!)"
  end

  defp truncate_string(nil, _max_length), do: ""

  defp truncate_string(string, max_length)
       when is_binary(string) and byte_size(string) <= max_length do
    string
  end

  defp truncate_string(string, max_length) when is_binary(string) do
    String.slice(string, 0, max_length - 3) <> "..."
  end

  defp sprintf(format, args) do
    :io_lib.format(format, args) |> to_string()
  end
end
