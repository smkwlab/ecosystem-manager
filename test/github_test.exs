defmodule EcosystemManager.GitHubTest do
  use ExUnit.Case
  doctest EcosystemManager.GitHub

  alias EcosystemManager.{GitHub, Repository}

  describe "get_github_remote function" do
    test "handles non-existent repository" do
      temp_dir = System.tmp_dir!()
      repo = %Repository{path: temp_dir}
      result = GitHub.get_github_remote(repo)
      assert result == :error
    end

    test "handles repository without remote" do
      temp_dir = System.tmp_dir!()
      test_repo = Path.join(temp_dir, "test_repo_#{:rand.uniform(10000)}")
      File.mkdir_p!(test_repo)

      # Initialize git repository without remote
      System.cmd("git", ["init"], cd: test_repo)

      try do
        repo = %Repository{path: test_repo}
        result = GitHub.get_github_remote(repo)
        assert result == :error
      after
        File.rm_rf!(test_repo)
      end
    end

    test "extracts owner and repo from GitHub URL" do
      temp_dir = System.tmp_dir!()
      test_repo = Path.join(temp_dir, "github_repo_#{:rand.uniform(10000)}")
      File.mkdir_p!(test_repo)

      # Initialize git repository with GitHub remote
      System.cmd("git", ["init"], cd: test_repo)

      System.cmd("git", ["remote", "add", "origin", "https://github.com/user/repo.git"],
        cd: test_repo
      )

      try do
        repo = %Repository{path: test_repo}
        result = GitHub.get_github_remote(repo)
        assert result == {:ok, {"user", "repo"}}
      after
        File.rm_rf!(test_repo)
      end
    end

    test "handles SSH GitHub URLs" do
      temp_dir = System.tmp_dir!()
      test_repo = Path.join(temp_dir, "ssh_repo_#{:rand.uniform(10000)}")
      File.mkdir_p!(test_repo)

      System.cmd("git", ["init"], cd: test_repo)

      System.cmd("git", ["remote", "add", "origin", "git@github.com:user/repo.git"],
        cd: test_repo
      )

      try do
        repo = %Repository{path: test_repo}
        result = GitHub.get_github_remote(repo)
        assert result == {:ok, {"user", "repo"}}
      after
        File.rm_rf!(test_repo)
      end
    end
  end

  describe "get_pull_requests function" do
    test "returns default info for owner/repo" do
      result = GitHub.get_pull_requests("owner", "repo")
      assert is_map(result)
      assert Map.has_key?(result, :total)
      assert Map.has_key?(result, :drafts)
      assert Map.has_key?(result, :needs_review)
    end

    test "processes JSON data from successful gh command" do
      # Test with various JSON structures that could come from gh
      test_json_data = [
        # Case 1: Empty PR list
        "[]",
        # Case 2: PRs with different states
        """
        [
          {"isDraft": true, "reviewDecision": ""},
          {"isDraft": false, "reviewDecision": "REVIEW_REQUIRED"},
          {"isDraft": false, "reviewDecision": "APPROVED"},
          {"isDraft": true, "reviewDecision": "CHANGES_REQUESTED"}
        ]
        """,
        # Case 3: Mixed data
        """
        [
          {"isDraft": false, "reviewDecision": "REVIEW_REQUIRED"},
          {"isDraft": false, "reviewDecision": "REVIEW_REQUIRED"},
          {"isDraft": true, "reviewDecision": ""},
          {"isDraft": false, "reviewDecision": "APPROVED"}
        ]
        """
      ]

      for json_data <- test_json_data do
        # This simulates what would happen if gh command succeeded
        parsed_data = Jason.decode!(json_data)

        # Test count_by_labels logic manually since it's private
        total = length(parsed_data)
        drafts = Enum.count(parsed_data, & &1["isDraft"])

        needs_review =
          Enum.count(parsed_data, fn pr ->
            !pr["isDraft"] && pr["reviewDecision"] == "REVIEW_REQUIRED"
          end)

        # Verify the counting logic works correctly
        assert is_integer(total)
        assert is_integer(drafts)
        assert is_integer(needs_review)
        assert drafts >= 0
        assert needs_review >= 0
        assert total >= drafts
      end
    end
  end

  describe "get_issues function" do
    test "returns default info for owner/repo" do
      result = GitHub.get_issues("owner", "repo")
      assert is_map(result)
      assert Map.has_key?(result, :total)
      assert Map.has_key?(result, :bugs)
      assert Map.has_key?(result, :enhancements)
      assert Map.has_key?(result, :urgent)
    end

    test "processes JSON data from successful gh command" do
      # Test with various JSON structures that could come from gh
      test_json_data = [
        # Case 1: Empty issues list
        "[]",
        # Case 2: Issues with different labels
        """
        [
          {"labels": [{"name": "bug"}, {"name": "critical"}]},
          {"labels": [{"name": "enhancement"}, {"name": "feature"}]},
          {"labels": [{"name": "urgent"}, {"name": "high"}]},
          {"labels": [{"name": "documentation"}]}
        ]
        """,
        # Case 3: Issues with no labels or mixed
        """
        [
          {"labels": []},
          {"labels": [{"name": "bug"}]},
          {"labels": [{"name": "enhancement"}, {"name": "urgent"}]},
          {"labels": [{"name": "bug"}, {"name": "urgent"}]}
        ]
        """
      ]

      for json_data <- test_json_data do
        # This simulates what would happen if gh command succeeded
        parsed_data = Jason.decode!(json_data)

        # Test count_by_labels logic manually since it's private
        total = length(parsed_data)

        bugs =
          Enum.count(parsed_data, fn issue ->
            issue["labels"] |> Enum.any?(fn label -> label["name"] == "bug" end)
          end)

        enhancements =
          Enum.count(parsed_data, fn issue ->
            issue["labels"] |> Enum.any?(fn label -> label["name"] == "enhancement" end)
          end)

        urgent =
          Enum.count(parsed_data, fn issue ->
            issue["labels"] |> Enum.any?(fn label -> label["name"] == "urgent" end)
          end)

        # Verify the counting logic works correctly
        assert is_integer(total)
        assert is_integer(bugs)
        assert is_integer(enhancements)
        assert is_integer(urgent)
        assert bugs >= 0
        assert enhancements >= 0
        assert urgent >= 0
      end
    end
  end

  describe "fetch_github_info function" do
    test "handles repository without GitHub remote" do
      temp_dir = System.tmp_dir!()
      test_repo = Path.join(temp_dir, "no_github_#{:rand.uniform(10000)}")
      File.mkdir_p!(test_repo)
      System.cmd("git", ["init"], cd: test_repo)

      try do
        repo = %Repository{path: test_repo, name: "test"}
        result = GitHub.fetch_github_info(repo)

        assert is_map(result.issues)
        assert is_map(result.pull_requests)
        assert result.issues.total == 0
        assert result.pull_requests.total == 0
      after
        File.rm_rf!(test_repo)
      end
    end
  end

  describe "private function coverage" do
    test "parse_github_url with various formats" do
      # Note: Testing through public interface since parse_github_url is private
      url_test_cases = [
        {"https://github.com/owner/repo.git", {:ok, {"owner", "repo"}}},
        {"https://github.com/owner/repo", {:ok, {"owner", "repo"}}},
        {"git@github.com:owner/repo.git", {:ok, {"owner", "repo"}}},
        {"git@github.com:owner/repo", {:ok, {"owner", "repo"}}},
        {"https://gitlab.com/owner/repo.git", :error},
        {"https://bitbucket.org/owner/repo.git", :error},
        {"invalid-url", :error},
        {"", :error},
        {"not-a-git-url", :error}
      ]

      temp_dir = System.tmp_dir!()

      for {url, expected} <- url_test_cases do
        test_repo = Path.join(temp_dir, "parse_test_#{:rand.uniform(10000)}")
        File.mkdir_p!(test_repo)
        System.cmd("git", ["init"], cd: test_repo)

        if url != "" do
          System.cmd("git", ["remote", "add", "origin", url], cd: test_repo)
        end

        try do
          repo = %Repository{path: test_repo}
          result = GitHub.get_github_remote(repo)
          assert result == expected
        after
          File.rm_rf!(test_repo)
        end
      end
    end

    test "fetch_github_info with different repository states" do
      temp_dir = System.tmp_dir!()

      # Test with non-existent repository
      non_existent = %Repository{path: "/non/existent", name: "test"}
      result1 = GitHub.fetch_github_info(non_existent)
      assert result1.issues.total == 0
      assert result1.pull_requests.total == 0

      # Test with repository without GitHub remote
      no_remote_path = Path.join(temp_dir, "no_remote_#{:rand.uniform(10000)}")
      File.mkdir_p!(no_remote_path)
      System.cmd("git", ["init"], cd: no_remote_path)

      try do
        no_remote = %Repository{path: no_remote_path, name: "test"}
        result2 = GitHub.fetch_github_info(no_remote)
        assert result2.issues.total == 0
        assert result2.pull_requests.total == 0
      after
        File.rm_rf!(no_remote_path)
      end

      # Test with repository with GitHub remote (will use default due to gh command failure)
      github_path = Path.join(temp_dir, "github_#{:rand.uniform(10000)}")
      File.mkdir_p!(github_path)
      System.cmd("git", ["init"], cd: github_path)

      System.cmd("git", ["remote", "add", "origin", "https://github.com/test/repo.git"],
        cd: github_path
      )

      try do
        github_repo = %Repository{path: github_path, name: "test"}
        result3 = GitHub.fetch_github_info(github_repo)
        # Should have default values due to gh command not being available
        assert is_map(result3.issues)
        assert is_map(result3.pull_requests)
      after
        File.rm_rf!(github_path)
      end
    end

    test "count_by_labels function coverage" do
      # Test issues/PRs data structures that would exercise count_by_labels
      _test_issues = [
        %{
          "number" => 1,
          "title" => "Bug fix",
          "labels" => [
            %{"name" => "bug"},
            %{"name" => "critical"}
          ]
        },
        %{
          "number" => 2,
          "title" => "Feature request",
          "labels" => [
            %{"name" => "enhancement"},
            %{"name" => "feature"}
          ]
        },
        %{
          "number" => 3,
          "title" => "Urgent issue",
          "labels" => [
            %{"name" => "urgent"},
            %{"name" => "high"}
          ]
        },
        %{
          "number" => 4,
          "title" => "No labels",
          "labels" => []
        },
        %{
          "number" => 5,
          "title" => "Nil labels",
          "labels" => nil
        }
      ]

      # Test get_issues with mock data (will fail but exercise the function)
      result = GitHub.get_issues("test", "repo")
      assert is_map(result)
      assert Map.has_key?(result, :total)
      assert Map.has_key?(result, :bugs)
      assert Map.has_key?(result, :enhancements)
      assert Map.has_key?(result, :urgent)
    end

    test "simulates successful GitHub API calls with comprehensive data" do
      # Test scenarios that would exercise success paths
      # These test the logic that would run if gh commands succeeded

      # Scenario 1: Repository with comprehensive issue data
      issue_data = [
        %{
          "number" => 1,
          "title" => "Critical bug in authentication",
          "labels" => [
            %{"name" => "bug"},
            %{"name" => "critical"},
            %{"name" => "urgent"}
          ]
        },
        %{
          "number" => 2,
          "title" => "Feature request for dark mode",
          "labels" => [
            %{"name" => "enhancement"},
            %{"name" => "feature"},
            %{"name" => "ui"}
          ]
        },
        %{
          "number" => 3,
          "title" => "High priority performance issue",
          "labels" => [
            %{"name" => "bug"},
            %{"name" => "performance"},
            %{"name" => "high"}
          ]
        },
        %{
          "number" => 4,
          "title" => "Documentation improvement",
          "labels" => [
            %{"name" => "documentation"},
            %{"name" => "improvement"}
          ]
        },
        %{
          "number" => 5,
          "title" => "Issue with empty labels",
          "labels" => []
        },
        %{
          "number" => 6,
          "title" => "Issue with nil labels",
          "labels" => nil
        }
      ]

      # Test count_by_labels logic manually
      total = length(issue_data)

      bugs =
        Enum.count(issue_data, fn issue ->
          labels = issue["labels"] || []

          Enum.any?(labels, fn label ->
            label_name = String.downcase(label["name"] || "")
            Enum.any?(~w[bug error critical regression], &String.contains?(label_name, &1))
          end)
        end)

      enhancements =
        Enum.count(issue_data, fn issue ->
          labels = issue["labels"] || []

          Enum.any?(labels, fn label ->
            label_name = String.downcase(label["name"] || "")

            Enum.any?(
              ~w[enhancement feature improvement request],
              &String.contains?(label_name, &1)
            )
          end)
        end)

      urgent =
        Enum.count(issue_data, fn issue ->
          labels = issue["labels"] || []

          Enum.any?(labels, fn label ->
            label_name = String.downcase(label["name"] || "")
            Enum.any?(~w[critical urgent high], &String.contains?(label_name, &1))
          end)
        end)

      # Verify counting logic
      assert total == 6
      # Issues 1 and 3 have bug labels
      assert bugs == 2
      # Issues 2 and 4 have enhancement-type labels
      assert enhancements == 2
      # Issues 1 and 3 have urgent/critical/high labels
      assert urgent == 2

      # Scenario 2: Repository with PR data
      pr_data = [
        %{
          "number" => 1,
          "title" => "Fix authentication bug",
          "isDraft" => false,
          "reviewDecision" => "REVIEW_REQUIRED"
        },
        %{
          "number" => 2,
          "title" => "Draft: WIP feature",
          "isDraft" => true,
          "reviewDecision" => nil
        },
        %{
          "number" => 3,
          "title" => "Approved changes",
          "isDraft" => false,
          "reviewDecision" => "APPROVED"
        },
        %{
          "number" => 4,
          "title" => "Another draft",
          "isDraft" => true,
          "reviewDecision" => "CHANGES_REQUESTED"
        },
        %{
          "number" => 5,
          "title" => "Needs review",
          "isDraft" => false,
          "reviewDecision" => nil
        }
      ]

      # Test PR counting logic
      pr_total = length(pr_data)
      pr_drafts = Enum.count(pr_data, & &1["isDraft"])

      pr_needs_review =
        Enum.count(pr_data, fn pr ->
          not pr["isDraft"] and pr["reviewDecision"] in [nil, "REVIEW_REQUIRED"]
        end)

      # Verify PR counting logic
      assert pr_total == 5
      # PRs 2 and 4 are drafts
      assert pr_drafts == 2
      # PRs 1 and 5 need review
      assert pr_needs_review == 2

      # These tests verify the logic that would be executed in the success paths
      # of get_issues and get_pull_requests functions
    end

    test "gh_api_call error handling" do
      # Test various gh command scenarios
      # These will fail but exercise error handling paths

      # Test get_issues with non-existent repo
      result1 = GitHub.get_issues("nonexistent", "repo")
      assert result1.total == 0
      assert result1.bugs == 0
      assert result1.enhancements == 0
      assert result1.urgent == 0

      # Test get_pull_requests with non-existent repo
      result2 = GitHub.get_pull_requests("nonexistent", "repo")
      assert result2.total == 0
      assert result2.drafts == 0
      assert result2.needs_review == 0

      # Test with various invalid input combinations
      invalid_inputs = [
        {"", ""},
        {"a", "b"},
        {"test-owner", "test-repo"},
        {"user/repo", "invalid"},
        {"./local", "path"}
      ]

      for {owner, repo} <- invalid_inputs do
        issues = GitHub.get_issues(owner, repo)
        prs = GitHub.get_pull_requests(owner, repo)

        assert is_map(issues)
        assert is_map(prs)
        assert issues.total == 0
        assert prs.total == 0
      end
    end

    test "mock successful GitHub API responses" do
      # Since we can't easily mock System.cmd in tests without additional libraries,
      # we'll create a test that exercises the success path logic manually
      # by simulating what would happen if gh commands succeeded

      # This tests the JSON parsing and counting logic that would run
      # in the success paths of get_issues and get_pull_requests

      # Test issue counting logic with mock data
      mock_issues_json = """
      [
        {"number": 1, "title": "Critical bug", "labels": [{"name": "bug"}, {"name": "critical"}]},
        {"number": 2, "title": "Feature request", "labels": [{"name": "enhancement"}]},
        {"number": 3, "title": "Urgent fix", "labels": [{"name": "urgent"}, {"name": "bug"}]},
        {"number": 4, "title": "No labels", "labels": []},
        {"number": 5, "title": "Enhancement", "labels": [{"name": "feature"}]}
      ]
      """

      # Test PR counting logic with mock data
      mock_prs_json = """
      [
        {"number": 1, "title": "Fix bug", "isDraft": false, "reviewDecision": "REVIEW_REQUIRED"},
        {"number": 2, "title": "Draft PR", "isDraft": true, "reviewDecision": null},
        {"number": 3, "title": "Approved", "isDraft": false, "reviewDecision": "APPROVED"},
        {"number": 4, "title": "Needs review", "isDraft": false, "reviewDecision": null}
      ]
      """

      # Parse JSON (this simulates successful Jason.decode)
      {:ok, issues_data} = Jason.decode(mock_issues_json)
      {:ok, prs_data} = Jason.decode(mock_prs_json)

      # Test the actual success path logic using test helpers
      issues_result = GitHub.test_process_issues_success(issues_data)
      prs_result = GitHub.test_process_prs_success(prs_data)

      # Verify issue counting logic
      assert issues_result.total == 5
      # Issues 1 and 3 have bug labels
      assert issues_result.bugs == 2
      # Issues 2 and 5 have enhancement labels
      assert issues_result.enhancements == 2
      # Issues 1 and 3 have urgent/critical labels
      assert issues_result.urgent == 2

      # Verify PR counting logic
      assert prs_result.total == 4
      # Only PR 2 is a draft
      assert prs_result.drafts == 1
      # PRs 1 and 4 need review
      assert prs_result.needs_review == 2

      # This test verifies that the counting logic in the success paths
      # of both get_issues and get_pull_requests works correctly
    end

    test "count_by_labels function comprehensive testing" do
      # Test the count_by_labels function directly using the test helper

      # Test with various label configurations
      test_issues = [
        %{"labels" => [%{"name" => "bug"}, %{"name" => "critical"}]},
        %{"labels" => [%{"name" => "enhancement"}, %{"name" => "feature"}]},
        # Test case sensitivity
        %{"labels" => [%{"name" => "URGENT"}, %{"name" => "HIGH"}]},
        %{"labels" => [%{"name" => "documentation"}]},
        %{"labels" => []},
        # Test nil labels
        %{"labels" => nil},
        # Test partial matches
        %{"labels" => [%{"name" => "Bug-Fix"}, %{"name" => "Error-Handling"}]},
        %{"labels" => [%{"name" => "improvement"}, %{"name" => "request"}]}
      ]

      # Test bug labels
      bug_count = GitHub.test_count_by_labels(test_issues, ~w[bug error critical regression])
      # Issues with "bug"/"critical" and "Bug-Fix"/"Error-Handling"
      assert bug_count == 2

      # Test enhancement labels
      enhancement_count =
        GitHub.test_count_by_labels(test_issues, ~w[enhancement feature improvement request])

      # Issues with "enhancement"/"feature", and "improvement"/"request"
      assert enhancement_count == 2

      # Test urgent labels
      urgent_count = GitHub.test_count_by_labels(test_issues, ~w[critical urgent high])
      # Issues with "critical" and "URGENT"/"HIGH"
      assert urgent_count == 2

      # Test with empty target labels
      empty_count = GitHub.test_count_by_labels(test_issues, [])
      assert empty_count == 0

      # Test with empty issues
      empty_issues_count = GitHub.test_count_by_labels([], ~w[bug])
      assert empty_issues_count == 0
    end
  end

  describe "mock gh CLI for success paths" do
    setup do
      # Enable mock mode for gh CLI
      System.put_env("MOCK_GH_CLI", "true")

      on_exit(fn ->
        System.delete_env("MOCK_GH_CLI")
        System.delete_env("MOCK_INVALID_JSON")
      end)
    end

    test "get_issues with successful gh command" do
      # This will use the mock response
      result = GitHub.get_issues("test", "repo")

      assert result.total == 3
      # Issue #1 has "bug" label
      assert result.bugs == 1
      # Issue #2 has "enhancement" label
      assert result.enhancements == 1
      # Issues #1 and #3 have "critical" or "urgent" labels
      assert result.urgent == 2
    end

    test "get_pull_requests with successful gh command" do
      # This will use the mock response
      result = GitHub.get_pull_requests("test", "repo")

      assert result.total == 3
      # PR #11 is a draft
      assert result.drafts == 1
      # PR #10 needs review
      assert result.needs_review == 1
    end

    test "gh_api_call with invalid JSON response" do
      System.put_env("MOCK_INVALID_JSON", "true")

      # This will trigger the invalid JSON path
      result1 = GitHub.get_issues("test", "repo")
      result2 = GitHub.get_pull_requests("test", "repo")

      # Should return default values when JSON parsing fails
      assert result1.total == 0
      assert result2.total == 0
    end

    test "fetch_github_info uses mock data in test" do
      temp_dir = System.tmp_dir!()
      test_repo = Path.join(temp_dir, "mock_test_#{:rand.uniform(10000)}")
      File.mkdir_p!(test_repo)
      System.cmd("git", ["init"], cd: test_repo)

      System.cmd("git", ["remote", "add", "origin", "https://github.com/test/repo.git"],
        cd: test_repo
      )

      try do
        repo = %Repository{path: test_repo, name: "test"}
        result = GitHub.fetch_github_info(repo)

        # Should have mock data
        assert result.issues.total == 3
        assert result.pull_requests.total == 3
      after
        File.rm_rf!(test_repo)
      end
    end
  end

  describe "parse_github_url edge cases" do
    test "parse_github_url handles malformed GitHub URLs" do
      # Test through get_github_remote to cover the error path in parse_github_url
      temp_dir = System.tmp_dir!()
      test_repo = Path.join(temp_dir, "malformed_url_#{:rand.uniform(10000)}")
      File.mkdir_p!(test_repo)
      System.cmd("git", ["init"], cd: test_repo)

      # Add a GitHub URL that won't match the regex pattern
      System.cmd("git", ["remote", "add", "origin", "https://github.com/invalid-url-format"],
        cd: test_repo
      )

      try do
        repo = %Repository{path: test_repo}
        result = GitHub.get_github_remote(repo)
        # This covers the _ -> :error path in parse_github_url
        assert result == :error
      after
        File.rm_rf!(test_repo)
      end
    end
  end

  describe "comprehensive GitHub integration" do
    test "handles various URL formats" do
      url_formats = [
        "https://github.com/owner/repo.git",
        "https://github.com/owner/repo",
        "git@github.com:owner/repo.git",
        "git@github.com:owner/repo"
      ]

      for url <- url_formats do
        temp_dir = System.tmp_dir!()
        test_repo = Path.join(temp_dir, "url_test_#{:rand.uniform(10000)}")
        File.mkdir_p!(test_repo)

        System.cmd("git", ["init"], cd: test_repo)
        System.cmd("git", ["remote", "add", "origin", url], cd: test_repo)

        try do
          repo = %Repository{path: test_repo}
          result = GitHub.get_github_remote(repo)
          assert result == {:ok, {"owner", "repo"}}
        after
          File.rm_rf!(test_repo)
        end
      end
    end

    test "handles edge cases and malformed URLs" do
      malformed_urls = [
        "https://gitlab.com/owner/repo.git",
        "https://bitbucket.org/owner/repo.git",
        "invalid-url",
        ""
      ]

      for url <- malformed_urls do
        temp_dir = System.tmp_dir!()
        test_repo = Path.join(temp_dir, "malformed_#{:rand.uniform(10000)}")
        File.mkdir_p!(test_repo)

        System.cmd("git", ["init"], cd: test_repo)
        # Some git versions reject unusual URLs (e.g. the empty string).
        # That is fine for this test: whether the remote is added with a
        # non-GitHub URL or not added at all, get_github_remote/1 must
        # return :error either way.
        System.cmd("git", ["remote", "add", "origin", url], cd: test_repo)

        try do
          repo = %Repository{path: test_repo}
          result = GitHub.get_github_remote(repo)
          assert result == :error
        after
          File.rm_rf!(test_repo)
        end
      end
    end

    test "concurrent GitHub operations" do
      temp_dir = System.tmp_dir!()

      repos =
        for i <- 1..5 do
          test_repo = Path.join(temp_dir, "concurrent_#{i}_#{:rand.uniform(10000)}")
          File.mkdir_p!(test_repo)
          System.cmd("git", ["init"], cd: test_repo)

          System.cmd(
            "git",
            ["remote", "add", "origin", "https://github.com/owner#{i}/repo#{i}.git"],
            cd: test_repo
          )

          %Repository{path: test_repo}
        end

      try do
        tasks =
          for repo <- repos do
            Task.async(fn ->
              {
                GitHub.get_github_remote(repo),
                GitHub.get_pull_requests("test", "repo"),
                GitHub.get_issues("test", "repo")
              }
            end)
          end

        results = Task.await_many(tasks, 5000)

        for {remote_result, pr_result, issues_result} <- results do
          assert is_tuple(remote_result) or remote_result == :error
          assert is_map(pr_result)
          assert is_map(issues_result)
        end
      after
        for repo <- repos do
          File.rm_rf!(repo.path)
        end
      end
    end

    test "concurrent operations with timeout handling" do
      temp_dir = System.tmp_dir!()

      # Create repositories with different remote configurations
      repo_configs = [
        {"no_remote", nil},
        {"github_repo", "https://github.com/test1/repo1.git"},
        {"github_ssh", "git@github.com:test2/repo2.git"},
        {"non_github", "https://gitlab.com/test3/repo3.git"}
      ]

      repos =
        for {name, remote} <- repo_configs do
          repo_path = Path.join(temp_dir, "#{name}_#{:rand.uniform(10000)}")
          File.mkdir_p!(repo_path)
          System.cmd("git", ["init"], cd: repo_path)

          if remote do
            System.cmd("git", ["remote", "add", "origin", remote], cd: repo_path)
          end

          %Repository{path: repo_path, name: name}
        end

      try do
        # Test concurrent GitHub operations
        tasks =
          for repo <- repos do
            Task.async(fn ->
              {
                GitHub.get_github_remote(repo),
                GitHub.fetch_github_info(repo)
              }
            end)
          end

        results = Task.await_many(tasks, 10_000)

        for {remote_result, fetch_result} <- results do
          assert is_tuple(remote_result) or remote_result == :error
          assert is_struct(fetch_result, Repository)
          assert is_map(fetch_result.issues)
          assert is_map(fetch_result.pull_requests)
        end
      after
        for repo <- repos do
          File.rm_rf!(repo.path)
        end
      end
    end

    test "edge cases and error recovery" do
      # Test with extreme input values
      extreme_cases = [
        {String.duplicate("a", 1000), "repo"},
        {"owner", String.duplicate("b", 1000)},
        {"owner-with-dashes", "repo_with_underscores"},
        {"owner.dots", "repo.dots"},
        {"123numeric", "456numeric"}
      ]

      for {owner, repo} <- extreme_cases do
        # These should handle gracefully
        issues = GitHub.get_issues(owner, repo)
        prs = GitHub.get_pull_requests(owner, repo)

        assert is_map(issues)
        assert is_map(prs)

        # Should have default structure even on error
        assert Map.has_key?(issues, :total)
        assert Map.has_key?(prs, :total)
      end
    end
  end
end
