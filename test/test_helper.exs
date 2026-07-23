# Start ExUnit
ExUnit.start()

# CLI の exit_with_code をテストから検証できるよう、System.halt の代わりに
# throw({:cli_test_exit, code}) させる（ToolKit.CLI.Exit の test_mode 規約）
Application.put_env(:ecosystem_manager, :test_mode, true)

# Keep every test away from the developer's real ~/.config/ecosystem-manager:
# tests that do not manage ECOSYSTEM_MANAGER_CONFIG_DIR themselves (e.g. the
# CLI init-config test) write into this throwaway directory instead.
default_config_dir =
  Path.join(
    System.tmp_dir!(),
    "ecosystem_manager_test_config_#{:erlang.unique_integer([:positive])}"
  )

System.put_env("ECOSYSTEM_MANAGER_CONFIG_DIR", default_config_dir)

# Remove the throwaway directory once the suite finishes (it may not even
# exist if no test wrote to it).
ExUnit.after_suite(fn _result ->
  File.rm_rf!(default_config_dir)
  :ok
end)
