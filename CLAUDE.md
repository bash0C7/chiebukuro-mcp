# CLAUDE.md — chiebukuro-mcp

## 概要
Ruby ナレッジ DB 向けの読み取り専用 SQLite MCP サーバー。

## 主要クラス
- `ChiebukuroMcp::QueryTool` — SELECT/WITH のみ許可（INSERT/UPDATE/DELETE/DROP は ArgumentError）
- `ChiebukuroMcp::SemanticSearchTool` — vec0 KNN 検索、デフォルト limit 5
- `ChiebukuroMcp::SchemaResource` — DB スキーマ + _sqlite_mcp_meta 説明文を返す

## テスト
- `ruby_knowledge_store` に依存（Gemfile で `path: '../ruby-knowledge-store'`）
- `bundle exec rake test`

## 依存
- ruby_knowledge_store（ローカル path）, sqlite3, sqlite-vec, mcp
