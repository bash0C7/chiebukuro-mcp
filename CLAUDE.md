# CLAUDE.md — chiebukuro-mcp

## 概要
Ruby ナレッジ DB 向けの読み取り専用 SQLite MCP サーバー。

## 主要クラス
- `ChiebukuroMcp::QueryTool` — SELECT/WITH のみ許可（INSERT/UPDATE/DELETE/DROP は ArgumentError）
- `ChiebukuroMcp::SemanticSearchTool` — vec0 KNN 検索、デフォルト limit 5
- `ChiebukuroMcp::SchemaResource` — DB スキーマ + _sqlite_mcp_meta 説明文を返す

## テスト
- `bundle exec rake test`
- テスト用 DB は `TestDbHelper` モジュール（`test/test_helper.rb`）が直接構築（外部 gem 依存なし）

## 依存
- sqlite3, sqlite-vec, mcp
