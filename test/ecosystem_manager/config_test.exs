defmodule EcosystemManager.ConfigTest do
  use ExUnit.Case
  doctest EcosystemManager.Config

  alias EcosystemManager.Config

  describe "configuration access" do
    test "default_concurrency/0 returns configured or default value" do
      assert Config.default_concurrency() == 8
    end

    test "github_timeout/0 returns configured or default value" do
      assert Config.github_timeout() == 15_000
    end

    test "git_timeout/0 returns configured or default value" do
      assert Config.git_timeout() == 5_000
    end

    test "default_format/0 returns configured or default value" do
      assert Config.default_format() == :compact
    end

    test "cache_enabled?/0 returns configured or default value" do
      assert Config.cache_enabled?() == false
    end

    test "cache_ttl/0 returns configured or default value" do
      assert Config.cache_ttl() == 300_000
    end

    test "timing_enabled?/0 returns configured or default value" do
      assert Config.timing_enabled?() == false
    end

    test "github_api_base_url/0 returns configured or default value" do
      assert Config.github_api_base_url() == "https://api.github.com"
    end

    test "default_include_github/0 returns configured or default value" do
      assert Config.default_include_github() == true
    end

    test "all/0 returns all configuration as keyword list" do
      config = Config.all()

      assert Keyword.has_key?(config, :default_concurrency)
      assert Keyword.has_key?(config, :github_timeout)
      assert Keyword.has_key?(config, :git_timeout)
      assert Keyword.has_key?(config, :default_format)
      assert Keyword.has_key?(config, :cache_enabled)
      assert Keyword.has_key?(config, :cache_ttl)
      assert Keyword.has_key?(config, :timing_enabled)
      assert Keyword.has_key?(config, :github_api_base_url)
      assert Keyword.has_key?(config, :default_include_github)
      assert Keyword.has_key?(config, :workspace_path)
      assert Keyword.has_key?(config, :repositories)
    end
  end

  describe "repositories configuration" do
    test "repositories/0 returns configured repositories or nil" do
      result = Config.repositories()

      # Should be either nil or a list
      assert is_nil(result) or is_list(result)
    end
  end

  describe "configuration fallbacks" do
    setup do
      # Snapshot and always restore the application env, even when an
      # assertion in the test fails midway
      keys = [:default_concurrency, :github_timeout, :default_format]
      originals = Enum.map(keys, &{&1, Application.get_env(:ecosystem_manager, &1)})

      on_exit(fn ->
        Enum.each(originals, fn
          {key, nil} -> Application.delete_env(:ecosystem_manager, key)
          {key, value} -> Application.put_env(:ecosystem_manager, key, value)
        end)
      end)

      :ok
    end

    test "functions return defaults when application config is missing" do
      # Test that functions work even when specific config is not set
      Application.delete_env(:ecosystem_manager, :default_concurrency)
      assert Config.default_concurrency() == 8

      Application.delete_env(:ecosystem_manager, :github_timeout)
      assert Config.github_timeout() == 15_000

      Application.delete_env(:ecosystem_manager, :default_format)
      assert Config.default_format() == :compact
    end
  end

  describe "runtime configuration changes" do
    setup do
      # Snapshot and always restore, even when an assertion fails midway
      original = Application.get_env(:ecosystem_manager, :default_concurrency)

      on_exit(fn ->
        if original do
          Application.put_env(:ecosystem_manager, :default_concurrency, original)
        else
          Application.delete_env(:ecosystem_manager, :default_concurrency)
        end
      end)

      %{original_concurrency: Config.default_concurrency()}
    end

    test "configuration can be changed at runtime", %{original_concurrency: original} do
      Application.put_env(:ecosystem_manager, :default_concurrency, 16)
      assert Config.default_concurrency() == 16

      Application.put_env(:ecosystem_manager, :default_concurrency, original)
      assert Config.default_concurrency() == original
    end
  end
end
