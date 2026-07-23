defmodule EcosystemManager.MixProject do
  use Mix.Project

  def project do
    [
      app: :ecosystem_manager,
      version: "0.1.0",
      # Keep in sync with the LTS Elixir lane of the org-standard CI
      # (smkwlab/.github elixir-ci.yml)
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: [main_module: EcosystemManager.CLI, name: "ecosystem-manager"],
      # Matches the org-standard registry-manager coverage config: a summary
      # threshold (informational, does not hard-fail the build) rather than a
      # gate. The CLI escript layer is exercised via integration, not units.
      test_coverage: [
        summary: [threshold: 80],
        ignore_modules: [
          EcosystemManager.UserConfig
        ]
      ],
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_add_apps: [:mix],
        flags: [:error_handling, :underspecs, :unmatched_returns],
        ignore_warnings: "dialyzer.ignore-warnings.exs"
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {EcosystemManager.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:tool_kit, github: "smkwlab/elixir-tool-kit", tag: "v0.2.0"},
      {:jason, "~> 1.4"},
      # Explicit dependency: user config (config.yml) is parsed with
      # YamlElixir directly, not only through tool_kit
      {:yaml_elixir, "~> 2.9"},
      {:req, "~> 0.4"},
      # Development and testing tools
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end
end
