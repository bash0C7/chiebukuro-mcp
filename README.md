# chiebukuro-mcp

Read-only SQLite MCP server. Connects to one or more SQLite databases (with optional vec0 semantic search) and exposes them as MCP tools.

Per-database tool names are derived from the config key:
- `chiebukuro_query_<db_name>` — SELECT / WITH only (INSERT/UPDATE/DELETE/DROP are rejected)
- `chiebukuro_semantic_search_<db_name>` — KNN vector search via vec0 (only registered if `semantic_search` config is present)

## Configuration

The server reads a JSON config file. Pass the path via the `CHIEBUKURO_CONFIG` environment variable.

```json
{
  "databases": {
    "my_db": {
      "path": "/absolute/path/to/database.db",
      "description": "Description shown in the MCP tool",
      "semantic_search": {
        "vec_table": "memories_vec",
        "content_table": "memories",
        "content_column": "content",
        "source_column": "source",
        "join_key": "memory_id"
      }
    }
  }
}
```

`semantic_search` is optional. Omit it for databases without vec0 tables.

## Inspecting a database

Use the `inspect` subcommand to generate a suggested config entry for any SQLite database:

```bash
bundle exec exe/chiebukuro-mcp inspect /path/to/database.db
```

The output includes `suggested_config` with auto-detected `semantic_search` settings if vec0 tables are found.

## Claude Code integration

In your `~/.claude/settings.json`:

```json
"mcpServers": {
  "chiebukuro-mcp": {
    "type": "stdio",
    "command": "ruby",
    "args": ["/path/to/chiebukuro-mcp/lib/chiebukuro_mcp/run.rb"],
    "env": {
      "CHIEBUKURO_CONFIG": "/path/to/chiebukuro.json"
    }
  }
}
```

The `chiebukuro.json` config file should live in your environment-specific dotfiles, not in this repo.

## Development

```bash
bundle config set --local path vendor/bundle
bundle install
bundle exec rake test
```
