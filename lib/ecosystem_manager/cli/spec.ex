defmodule EcosystemManager.CLI.Spec do
  @moduledoc """
  CLI のコマンド・オプション定義の単一ソース。

  定義(オプションカタログ・コマンド表)はこのモジュールが持ち、
  OptionParser に渡す strict/aliases、コマンドごとの有効オプション検証、
  help 文面の導出は `ToolKit.CLI.Spec` に委譲する。
  ここに定義がないオプションはパース段階でエラーになる。
  """

  alias ToolKit.CLI.Spec, as: EngineSpec

  @option_catalog %{
    help: %{type: :boolean, alias: :h, values: nil, doc: "このヘルプを表示"},
    workspace: %{
      type: :string,
      alias: :w,
      values: nil,
      doc: "対象ワークスペース名（workspace --list 参照）"
    },
    long: %{type: :boolean, alias: :l, values: nil, doc: "詳細テーブル表示"},
    fast: %{type: :boolean, alias: nil, values: nil, doc: "GitHub API を呼ばない高速モード"},
    no_cache: %{type: :boolean, alias: nil, values: nil, doc: "キャッシュを使用しない"},
    all: %{type: :boolean, alias: nil, values: nil, doc: "設定済みの全ワークスペースを対象にする"},
    urgent_issues: %{type: :boolean, alias: nil, values: nil, doc: "緊急 issue のあるリポジトリのみ表示"},
    with_prs: %{type: :boolean, alias: nil, values: nil, doc: "open PR のあるリポジトリのみ表示"},
    needs_review: %{
      type: :boolean,
      alias: nil,
      values: nil,
      doc: "レビュー待ち PR のあるリポジトリのみ表示"
    },
    max_concurrency: %{
      type: :integer,
      alias: nil,
      values: nil,
      doc: "並列実行数の上限（デフォルト: 8）"
    },
    time_sort: %{type: :boolean, alias: :t, values: nil, doc: "最終 commit 時刻順でソート"},
    reverse: %{type: :boolean, alias: :r, values: nil, doc: "ソート順を反転"},
    sync: %{
      type: :boolean,
      alias: nil,
      values: nil,
      doc: "リポジトリを自動発見して user config に書き込み、ワークスペースを登録"
    },
    name: %{type: :string, alias: nil, values: nil, doc: "登録するワークスペース名を上書き"},
    list: %{type: :boolean, alias: nil, values: nil, doc: "設定済みワークスペースを一覧表示"}
  }

  @global_option_names [:help, :workspace]

  @commands [
    %{
      name: "list",
      aliases: ["ls"],
      usage: ["list", "ls"],
      summary: "全リポジトリの状態を一覧表示（サブコマンド省略時の既定）",
      options: [
        :long,
        :fast,
        :no_cache,
        :all,
        :urgent_issues,
        :with_prs,
        :needs_review,
        :max_concurrency,
        :time_sort,
        :reverse
      ],
      examples: [
        "list",
        "ls",
        "list --long",
        "list --fast",
        "list --no-cache",
        "list --all",
        "list -w dns",
        "list -t",
        "list -t -r"
      ]
    },
    %{
      name: "config",
      aliases: [],
      usage: ["config"],
      summary: "現在の設定を表示",
      options: [],
      examples: ["config"]
    },
    %{
      name: "repos",
      aliases: [],
      usage: ["repos", "repos --sync"],
      summary: "リポジトリ構成と設定ソースを表示（--sync で自動発見して登録）",
      options: [:sync, :name],
      examples: ["repos", "repos --sync", "repos --sync --name dns"]
    },
    %{
      name: "workspace",
      aliases: [],
      usage: ["workspace", "workspace --list"],
      summary: "解決されたワークスペースパスを表示（--list で一覧）",
      options: [:list],
      examples: ["workspace --list", "cd $(ecosystem-manager workspace)"]
    },
    %{
      name: "init-config",
      aliases: [],
      usage: ["init-config"],
      summary: "ユーザ設定の例ファイルを生成",
      options: [],
      examples: ["init-config"]
    },
    %{
      name: "help",
      aliases: [],
      usage: ["help"],
      summary: "このヘルプを表示",
      options: [],
      examples: ["help"]
    }
  ]

  @spec_struct %EngineSpec{
    tool_name: "ecosystem-manager",
    tool_summary: "エコシステムワークスペースの横断状態ツール",
    option_catalog: @option_catalog,
    global_option_names: @global_option_names,
    commands: @commands
  }

  @doc "ToolKit の CLI エンジンに渡す spec"
  def spec, do: @spec_struct

  @doc "コマンド定義の一覧"
  def commands, do: @commands

  @doc "コマンド名の一覧"
  def command_names, do: Enum.map(@commands, & &1.name)

  @doc "名前からコマンド定義を引く"
  def find_command(name), do: EngineSpec.find_command(@spec_struct, name)

  @doc "コマンドが受け付けるオプション名の MapSet（未知のコマンドは nil）"
  def allowed_for(name), do: EngineSpec.allowed_for(@spec_struct, name)

  @doc "グローバル help を spec から生成する"
  def render_help, do: EngineSpec.render_help(@spec_struct)

  @doc "コマンド単体の help を spec から生成する（未知のコマンドは nil）"
  def render_command_help(name), do: EngineSpec.render_command_help(@spec_struct, name)
end
