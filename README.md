# chiebukuro-mcp

Read-only MCP server for multiple SQLite databases with optional vec0 semantic search.

Per-database tool names are derived from the config key:
- `chiebukuro_query_<db_name>` — SELECT / WITH only (INSERT/UPDATE/DELETE/DROP are rejected)
- `chiebukuro_semantic_search_<db_name>` — KNN vector search via vec0 (only registered if `semantic_search` config is present)

## Configuration

The server reads `~/chiebukuro-mcp/chiebukuro.json` on startup.

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

## Integration

The server is launched via `scripts/start_mcp.sh`, which explicitly uses rbenv's bundler to avoid system Ruby conflicts.

**Claude Code** — add to `~/.claude/settings.json`:

```json
"mcpServers": {
  "chiebukuro-mcp": {
    "type": "stdio",
    "command": "/path/to/chiebukuro-mcp/scripts/start_mcp.sh"
  }
}
```

**Claude Desktop** — add to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
"mcpServers": {
  "chiebukuro-mcp": {
    "command": "/path/to/chiebukuro-mcp/scripts/start_mcp.sh"
  }
}
```

`~/chiebukuro-mcp/chiebukuro.json` must exist before starting — see **Configuration** section above for the format. Keep it in your dotfiles, not this repo.

## Agent-ready MCP surface

For each configured DB the server now exposes, in addition to `chiebukuro_query_<db>` and `chiebukuro_semantic_search_<db>`:

- `chiebukuro_explain_query_<db>` — runs `EXPLAIN QUERY PLAN` against a read-only SELECT.
- `chiebukuro_query_with_clarification_<db>` — natural-language intent driven. Uses MCP elicitation to fill slots, then executes a recipe template. Falls back to plain-query guidance if the DB has no recipes.
- `schema://<db>` — Markdown description of tables and columns.
- `recipes://<db>` — Markdown catalogue of recipe query templates with interpretation notes.
- `hints://<db>` — Markdown catalogue of column enum values / sample values / note rules.

Plus one global tool:

- `chiebukuro_probe_capabilities` — reports whether the connected MCP host declared `sampling` and `elicitation` capabilities.

## Prefilled clarification params

`chiebukuro_query_with_clarification_<db>` exposes every `clarification_field` from the DB's yml as a **top-level optional param** of the tool itself. The host LLM (e.g. Claude Code) can pre-fill any of them from the user's natural-language intent — typically dates it parsed against the current date, or `source_like` patterns it mapped to known sources — and only slots that remain unresolved go through elicitation.

The tool description is automatically prefixed with an `[Agent usage]` hint that tells the agent:

- To parse date expressions (今日 / 昨日 / 今週 / 先週 / 最近 / N日前 / concrete dates) against the current date and pass them as date params.
- Not to pre-fill slots that have a yml-level `default` (typically `limit`) unless the user explicitly asked for a specific count — those are silently resolved server-side.

Resolution priority inside `IntentAnalyzer`:

1. `prefilled` (host LLM → tool params) — highest
2. keyword match on the intent string (via `clarification_fields[].hints.keywords`)
3. yml field-level `default`
4. otherwise: stays in `missing_fields` and is asked via elicitation form

`skip_if_resolved: true` (the default) removes any resolved slot from the elicitation form, so pre-filling is how the host avoids bothering the user.

The tool's `input_schema` is built dynamically from `clarification_fields`, so adding a slot to yml + re-running `apply_meta_patches.rb` is enough — no server code change needed.

## `_sqlite_mcp_meta` extended schema

Each DB can self-describe itself. `_sqlite_mcp_meta` has these columns:

| Column | Used by | Purpose |
| --- | --- | --- |
| `object_type` | all | `'db'` / `'table'` / `'column'` / `'recipe'` / `'clarification_field'` |
| `object_name` | all | target name (columns use `'table.column'`, recipes/slots use a label) |
| `description` | all | human-readable text |
| `hints_json` | `column`, `clarification_field` | JSON with `enum_values`, `sample_values`, `related_tables`, `note`, or slot attributes |
| `recipe_sql` | `recipe` | SELECT/WITH template, named placeholders `:key` allowed |
| `recipe_label` | `recipe` | short display label |

Older DBs with only the 3-column (`object_type`, `object_name`, `description`) table keep working; `MetaReader` silently returns empty recipes/hints for them.

## Graceful degradation

If a DB has no recipes and no clarification_fields, the server:

1. Logs a startup warning to stderr.
2. Still registers all tools and resources.
3. `query_with_clarification` short-circuits and returns a `fallback` action telling the caller to drive `chiebukuro_query_<db>` / `chiebukuro_semantic_search_<db>` directly, using `schema://<db>` for orientation.

The recipe/hints data itself is managed outside this repo — see `dotfiles/chiebukuro-mcp/scripts/meta_patches/*.yml`.

## Development

```bash
bundle config set --local path vendor/bundle
bundle install
bundle exec rake test
```
