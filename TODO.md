# TODO

## SemanticSearchTool のテーブル名ハードコード問題 + テスト環境整備

### 問題

`SemanticSearchTool` の SQL がテーブル名・カラム名をハードコードしている。

```ruby
# lib/chiebukuro_mcp/semantic_search_tool.rb
FROM memories_vec v
JOIN memories m ON m.id = v.memory_id
```

`chiebukuro.json` の `semantic_search` 設定（`vec_table` / `content_table` / `content_column` / `source_column` / `join_key`）が `SemanticSearchTool` に渡されていない。

現在の本番 DB は偶然同じ名前なので動いているが、別スキーマの DB を追加したとき壊れる。

### やること

**1. SemanticSearchTool を設定値ベースに変更**

`Server` から `sem_cfg` を `SemanticSearchTool.new` に渡し、SQL のテーブル名・カラム名を設定値から生成する。

**2. テスト環境の整備（Rails の test/fixtures 的なパターン）**

- `TestDbHelper` は現在 `memories` / `memories_vec` スキーマに特化している
- 任意のテーブル名・カラム名を指定して DB を作成できるよう拡張する
- `setup` / `teardown` で確実に作成・破棄されることを保証する
- 異なるテーブル名（例: `my_vecs` / `my_docs`）を持つ DB で semantic_search が動くテストを追加する（TDD: 先に RED）

### 優先度

低（現在の本番 DB はすべて同じスキーマ。新規 DB 追加時に対応でも可）
