# CLAUDE.md — chiebukuro-mcp

## 概要

任意の SQLite DB（vec0 セマンティック検索対応）を MCP ツールとして公開する読み取り専用サーバー。
環境依存の設定（DBパス等）は外部の `chiebukuro.json` で管理し、このリポジトリには含まない。

## エコシステムにおける本 gem の責務

chiebukuro-mcp gem は **SQLite を読んで MCP ツールとして提供するだけ** に徹する。

DB の生成・変換処理は本 gem の責務外:

- MacアプリのSQLiteコピー・バックアップ → dotfiles（chiebukuro-mcp 設定リポジトリ）
- JSON/テキスト → SQLite の変換（ワンショット） → dotfiles の `scripts/`
- JSON/テキスト → SQLite の変換（複雑・継続メンテ） → 別 collector プロジェクト

新しいデータソースを追加する際、変換処理を本 gem に持ち込まないこと。

## 主要クラス

| クラス | 役割 |
|--------|------|
| `ChiebukuroMcp::Server` | config を受け取り MCP ツール・リソースを構築。`run` でstdio起動 |
| `ChiebukuroMcp::QueryTool` | SELECT/WITH のみ許可。INSERT/UPDATE/DELETE/DROP は ArgumentError |
| `ChiebukuroMcp::SemanticSearchTool` | vec0 KNN 検索。デフォルト limit 5 |
| `ChiebukuroMcp::SchemaResource` | DB スキーマ + `_sqlite_mcp_meta` 説明文を返す |
| `ChiebukuroMcp::Inspector` | DBを解析して `suggested_config` を生成（`inspect` サブコマンド用） |
| `ChiebukuroMcp::Embedder` | `informers` gem で `ruri-v3-310m-onnx` をラップ。768次元ベクトルを生成（`serve` サブコマンド用） |

## 設定の流れ

```
chiebukuro.json (環境依存) → Server.new(config:, embedder:) → build_mcp_server → MCP tools/resources
```

`config` は `databases` キーを持つ Hash（または JSON.parse 結果）。

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
