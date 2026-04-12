# CLAUDE.md — chiebukuro-mcp

## 位置付け：AI データエージェント "chiebukuro" ファミリーの中核

**chiebukuro は AI データエージェントである。**

メルカリの Socrates に触発されつつ、ホスト LLM（Claude Code など）を「脳」、
chiebukuro ファミリーを「身体（道具・知識・対話手段）」として分業する構成で、
個人用のローカル AI データエージェントを実現する。

- **脳（Agent Loop / plan / reflect）** — ホスト LLM（現状は Claude Code）が担う
- **身体（Tools / Knowledge / Dialogue）** — chiebukuro ファミリーが担う
  - `chiebukuro-mcp`（本 gem）：読み取り専用の MCP サーバー本体
  - 将来の追加 repo（collector / agent / etc.）も必要に応じてファミリーに加える

この分業を支える事実（2026-04-10 時点の実証結果）:

- Claude Code は MCP の **elicitation capability を宣言している**（`chiebukuro_probe_capabilities` で確認済み）
- Claude Code は MCP の **sampling capability は宣言していない**
- → サーバー側で LLM を借りる sampling は不要。ホスト LLM が常時そこにいる前提で、
  ツール・リソース・elicitation を磨くほうが DRY で自然

## 概要

任意の SQLite DB（vec0 セマンティック検索対応）を MCP ツールとして公開する**読み取り専用**サーバー。
環境依存の設定（DBパス等）は外部の `chiebukuro.json` で管理し、このリポジトリには含まない。

## エコシステムにおける本 gem の責務

chiebukuro-mcp gem は **SQLite を読んで MCP ツール・リソース・対話手段として提供する**ことに徹する。

「読むだけに徹する」原則の具体化:

- **データの読み取り**：SELECT / WITH のみ（INSERT/UPDATE/DELETE/DROP は ArgumentError で拒否）
- **知識の提供**：schema リソース、将来的に recipes / hints リソース
- **対話の主導**：elicitation でユーザーに構造化質問を送り、曖昧なクエリ要求を具体化する
  （これは「書込み」ではなく「入力受付」なので読み取り専用原則と矛盾しない）

DB の生成・変換処理は本 gem の責務外:

- MacアプリのSQLiteコピー・バックアップ → dotfiles（chiebukuro-mcp 設定リポジトリ）
- JSON/テキスト → SQLite の変換（ワンショット） → dotfiles の `scripts/`
- JSON/テキスト → SQLite の変換（複雑・継続メンテ） → 別 collector プロジェクト

新しいデータソースを追加する際、変換処理を本 gem に持ち込まないこと。

## sampling を使わない理由

Claude Code セッション内で動く限り、ホスト LLM は常にそこにいる。
- 意図明確化、計画立案、ツール選択、反省・再試行、結果解釈 — すべてホスト LLM が担う
- chiebukuro-mcp がサーバー側から LLM を借りる必要がない
- 将来、Claude Code を使わないシナリオ（cron 夜間バッチ等）が発生したときに再検討する

## 主要クラス

### 基盤

| クラス | 役割 |
|--------|------|
| `ChiebukuroMcp::Server` | config を受け取り MCP ツール・リソースを構築。`run` でstdio起動 |
| `ChiebukuroMcp::MetaReader` | `_sqlite_mcp_meta` 読み取りの単一窓口。descriptions / hints / recipes を統一 API で返す。旧スキーマ DB にも例外なく対応 |
| `ChiebukuroMcp::Inspector` | DBを解析して `suggested_config` を生成（`inspect` サブコマンド用） |
| `ChiebukuroMcp::Embedder` | `informers` gem で `ruri-v3-310m-onnx` をラップ。768次元ベクトルを生成（`serve` サブコマンド用） |

### データ読み取りツール

| クラス | 役割 |
|--------|------|
| `ChiebukuroMcp::QueryTool` | SELECT/WITH のみ許可。INSERT/UPDATE/DELETE/DROP は ArgumentError |
| `ChiebukuroMcp::SemanticSearchTool` | vec0 KNN 検索。デフォルト limit 5 |
| `ChiebukuroMcp::ExplainQueryTool` | `EXPLAIN QUERY PLAN` を実行して返す読み取り専用ツール。SELECT/WITH 以外は拒否 |

### 知識リソース

| クラス | 役割 |
|--------|------|
| `ChiebukuroMcp::SchemaResource` | `schema://<db>` — DB スキーマ + テーブル/DB description を Markdown で提供 |
| `ChiebukuroMcp::RecipesResource` | `recipes://<db>` — `_sqlite_mcp_meta` の recipe 行から典型クエリ集を Markdown で提供 |
| `ChiebukuroMcp::HintsResource` | `hints://<db>` — カラム enum 候補 / サンプル値 / 関連テーブルを Markdown で提供 |

### 対話ツール（elicitation 駆動）

| クラス | 役割 |
|--------|------|
| `ChiebukuroMcp::QueryWithClarificationTool` | 曖昧な自然言語要求を受けて、elicitation でユーザーに期間・絞込条件を構造化入力させ、recipe テンプレートに基づいて SELECT を実行するオーケストレーター |
| `ChiebukuroMcp::IntentAnalyzer` | intent 文字列をキーワードマッチで解析し、未指定フィールドと resolved_hints を返す |
| `ChiebukuroMcp::ClarificationFormBuilder` | 未指定フィールドと meta_hints から MCP elicitation 用 JSON Schema（form mode 制約準拠）を動的生成 |
| `ChiebukuroMcp::SqlTemplateEngine` | recipe を intent キーワードで選択し、named placeholder を positional `?` に置換。SELECT/WITH 以外の template は拒否 |

### 実証ツール

| クラス | 役割 |
|--------|------|
| `ChiebukuroMcp::ProbeTool` | ホスト LLM の sampling / elicitation capability を実地確認する実証ツール |

## Graceful degradation（meta 欠損時のフォールバック）

DB 側に `_sqlite_mcp_meta` が未整備でも Server は落ちず動作する。具体的には:

- **Server 起動時**: `recipes` と `clarification_fields` が両方空の DB について stderr に WARN を出す。ツール登録は全て行う。
- **`QueryWithClarificationTool#call`**: `recipes` が空の DB に対しては elicitation を行わず、`action: "fallback"` を返して「`schema://` を参照して `chiebukuro_query_<db>` で直接 SELECT せよ」とガイドする。
- **`RecipesResource` / `HintsResource`**: 空でもリソースは返る。本文は「このDBにはまだ定義されていない」旨 1 行。
- **旧 3 列スキーマの DB**: `MetaReader` が PRAGMA で列検出し、新列が無い DB は旧スキーマ扱いで空の recipes/hints を返す。MCP サーバ側の変更なしで後方互換が保たれる。

## Prefilled clarification params（ホスト LLM による pre-fill）

`chiebukuro_query_with_clarification_<db>` は、各 DB の yml に定義された
`clarification_fields` を **tool の top-level optional params** として露出する。
ホスト LLM（Claude Code 等）が intent から日付・ソース等を先に解析して渡せるので、
elicitation で人間に聞く回数が減る。

- **動的 `input_schema`**: `Server#build_clarify_input_schema` が
  `clarification_fields` を走査して `{type, format, oneOf, description}` を組み立てる。
  yml に slot を追加 → `apply_meta_patches.rb` → サーバ再起動だけで新 param が生える。
  サーバ側コード変更は不要。
- **Agent usage hint prepend**: tool description の先頭に `Server::CLARIFY_AGENT_USAGE_HINT`
  を必ず貼る。「日付表現は current date 基準で parse して date param に入れろ」
  「yml に `default` がある slot は pre-fill するな（サーバ側で silently 解決する）」
  の 2 原則をエージェントに伝える。
- **解決優先順位** (`IntentAnalyzer#analyze`):
  1. `prefilled` (tool params 経由) — 最強
  2. `clarification_fields[].hints.keywords` の部分一致
  3. field-level `default` (yml)
  4. どれにも当てはまらない → `missing_fields` に残り elicitation form で問う
- **`skip_if_resolved: true`** (default): resolve 済み slot は missing_fields から除外 →
  form にも現れない。これが「pre-fill すれば聞かれない」の実装。
- **優先順位と `limit` default の帰結**: `limit` のように yml に `default: 20` を置いた slot は、
  ユーザが「5 件だけ」等と明示しない限り silently 20 で解決されて form に出ない。
  結果として「限界件数を毎回聞かれる」ストレスがなくなる。

関連クラス:

- `Server#build_clarify_input_schema` / `Server#clarify_field_to_json_schema`: 動的 schema 生成
- `IntentAnalyzer#analyze(intent, prefilled = {})`: 2 引数目が host LLM pre-fill
- `QueryWithClarificationTool#call(intent:, server_context:, **prefilled)`: kwargs で受ける

## 設定の流れ

```
chiebukuro.json (環境依存) → Server.new(config:, embedder:) → build_mcp_server → MCP tools/resources
```

`config` は `databases` キーを持つ Hash（または JSON.parse 結果）。

## `_sqlite_mcp_meta` 拡張スキーマ

DB が自己記述するためのメタテーブル。後方互換のため旧スキーマ（3列のみ）でも動作する。

| 列 | 型 | 用途 |
|---|---|---|
| `object_type` | TEXT | `'db'` / `'table'` / `'column'` / `'recipe'` / `'clarification_field'` |
| `object_name` | TEXT | 対象名。column は `'table.column'`、recipe は一意ラベル、clarification_field は slot 名 |
| `description` | TEXT | 人間向け説明 |
| `hints_json` | TEXT | column / clarification_field で使用。column は `{enum_values, sample_values, related_tables, note}`。clarification_field は `{type, required, order, keywords, enum_values, default}` を JSON で |
| `recipe_sql` | TEXT | recipe 用。SELECT/WITH テンプレート本文（named placeholder `:key` 使用可） |
| `recipe_label` | TEXT | recipe 用。人間向けラベル |

追加列は全て NULLABLE。旧 DB で列自体が存在しない場合、MetaReader が例外を握りつぶして空値を返す。

## テスト

```bash
bundle exec rake test
```

テスト用 DB は `TestDbHelper`（`test/test_helper.rb`）がインメモリで構築する。外部 DB 不要。

## 依存

- `sqlite3` — SQLite 接続
- `sqlite-vec` — vec0 KNN 検索
- `mcp` — MCP プロトコル実装

## 環境依存情報の置き場所

DBパス・Claude Code の MCP 設定・`chiebukuro.json` の実体は
このリポジトリには含めない。利用者の dotfiles で管理する。
