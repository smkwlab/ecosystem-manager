# EcosystemManager

高性能なLaTeX論文執筆環境のエコシステム管理ツール。並列処理により従来のBashスクリプト（12秒）から1.5秒へ**88%の性能向上**を実現。

## 特徴

- 🚀 **高速並列処理**: `Task.async_stream`による並列リポジトリ処理
- 📊 **GitHub API統合**: Issues/PR統計の自動取得
- 🧪 **高品質実装**: 91.22%テストカバレッジ、Credo・Dialyzer検証済み
- ⚙️ **柔軟な設定**: 並列度・フォーマット・フィルタリングオプション
- 🛡️ **エラーハンドリング**: 包括的なエラー処理とタイムアウト制御

## インストール

```bash
cd ecosystem_manager
mix deps.get
mix escript.build

# バイナリ作成
./ecosystem-manager status
```

## 設定

### Workspace Path設定

どのディレクトリからでもecosystem-managerを実行できるように、workspace pathを設定できます：

1. **設定ファイルの作成**
   ```bash
   ./ecosystem-manager init-config
   ```

2. **設定ファイルの編集**
   ```bash
   # ~/.config/ecosystem-manager/config.exs を編集
   vim ~/.config/ecosystem-manager/config.exs
   ```

3. **workspace_pathを設定**
   ```elixir
   import Config
   
   config :ecosystem_manager,
     workspace_path: "~/SynologyDrive/semi/LaTeX/latex-ecosystem"
   ```

設定後は、どのディレクトリからでも実行可能：
```bash
cd /任意のディレクトリ
ecosystem-manager status  # workspace_pathで指定したディレクトリで実行される
```

## 使用方法

```bash
# 全リポジトリの状況確認
./ecosystem-manager status

# GitHub情報なしの高速モード（80ms）
./ecosystem-manager status --no-github

# 詳細表示
./ecosystem-manager status --format long

# フィルタリング
./ecosystem-manager status --urgent-issues
./ecosystem-manager status --with-prs
./ecosystem-manager status --needs-review

# 並列度調整（デフォルト: 8）
./ecosystem-manager status --max-concurrency 4
```

## パフォーマンス

| モード | 実行時間 | 改善率 |
|--------|----------|--------|
| フルモード | ~1.5 seconds | 88% |
| 高速モード (--no-github) | ~80ms | 99.3% |
| 元のBash版 | 12+ seconds | - |

## 開発

```bash
# テスト実行
mix test

# カバレッジ確認
mix test --cover

# 品質チェック
mix format && mix credo && mix dialyzer
```

## 設定

### 設定ファイル

`config/config.exs` で動作設定をカスタマイズできます：

```elixir
config :ecosystem_manager,
  default_concurrency: 8,      # 並列処理数
  github_timeout: 15_000,      # GitHub APIタイムアウト(ms)
  git_timeout: 5_000,          # Gitコマンドタイムアウト(ms)
  default_format: :compact,    # デフォルト出力形式
  enable_cache: false,         # キャッシュ有効化(将来実装)
  enable_timing: false         # 実行時間測定
```

### 環境別設定

```elixir
# 開発環境
config :ecosystem_manager,
  enable_timing: true,
  default_concurrency: 4

# 本番環境  
config :ecosystem_manager,
  default_concurrency: 12,
  enable_cache: true
```

設定例は `config/config.example.exs` を参照してください。

### リポジトリ設定

監視対象のリポジトリは **workspace 直下から自動検出** されます。ハードコードされた
一覧は持たず、以下の順で解決します：

1. ユーザー設定の `repositories:`（明示指定があれば最優先）
2. 自動検出：workspace 直下の Git リポジトリのうち、エコシステム org
   （`ecosystem_org:` 設定、無ければ workspace 自身の `origin` owner から導出）
   に属するもの。`.`（workspace 自身）は常に含み、`*-test` は除外

```bash
# 現在の対象リポジトリと解決元を確認
./ecosystem-manager repos

# 自動検出結果をユーザー設定に書き出す（一覧を固定したい場合）
./ecosystem-manager repos --sync
```

`repos --sync` は実行した workspace を `~/.config/ecosystem-manager/config.exs`
の `workspaces:` に登録します（既存の設定は保持）。単一 workspace のときは検出結果を
`repositories:` にピン留めするので、workspace ルートで一度 `repos --sync` すれば
そのまま使える設定になります。エコシステム外のリポジトリ（無関係なプロジェクト等）が
混じっている場合は、書き出された一覧から手動で削除してください。

### 複数 workspace

複数のエコシステム（例 `~/prj/LaTeX/latex-ecosystem` と `~/prj/DNS/ecosystem`）を
1 つのツールで扱えます。各 workspace のルートで `repos --sync` すると `workspaces:` に
登録されます：

```elixir
config :ecosystem_manager,
  workspaces: [
    latex: "~/prj/LaTeX/latex-ecosystem",
    dns:   "~/prj/DNS/ecosystem"
  ]
```

workspace は次の順で選択されます：

1. `--workspace NAME`（`-w`）で明示指定
2. カレントディレクトリを含む workspace（最深一致で自動選択）
3. 登録が 1 つだけならそれ
4. どれにも該当しなければカレントディレクトリ

```bash
# 登録済み workspace の一覧
./ecosystem-manager workspace --list

# cd した先の workspace が対象になる
cd ~/prj/DNS/ecosystem && ./ecosystem-manager status

# 名前で明示指定
./ecosystem-manager status -w dns

# 全 workspace をまとめて表示
./ecosystem-manager status --all
```

複数 workspace が登録されている場合、リポジトリ一覧は各 workspace ごとに自動検出で
解決されます（グローバルな `repositories:` ピンは使われません）。

## アーキテクチャ

- **CLI**: コマンドライン処理とオプション解析
- **Config**: 設定管理と環境別設定
- **Workspace**: 複数 workspace の登録・解決（cwd 自動選択 / --workspace）
- **Repository**: Git情報取得とリポジトリ管理
- **GitHub**: GitHub API統合（Issues/PR統計）
- **Status**: 並列処理とフォーマット出力

