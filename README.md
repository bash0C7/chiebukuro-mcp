# chiebukuro-mcp

Read-only SQLite MCP server for querying Ruby knowledge DB. Provides `query` and `semantic_search` tools plus a `schema` resource.

## Tools

- `query` — executes read-only SQL (SELECT / WITH only)
- `semantic_search` — KNN vector search using vec0

## Usage with Claude Desktop

See `scripts/start_mcp.sh` in [ruby-knowledge-db](https://github.com/bash0C7/ruby-knowledge-db).

## Development

```bash
bundle config set --local path vendor/bundle
bundle install
bundle exec rake test
```
