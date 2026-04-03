require 'sqlite3'
require 'sqlite_vec'
require 'json'

module ChiebukuroMcp
  class Inspector
    def initialize(db_path)
      @db_path = db_path
    end

    def inspect_db
      db     = open_db
      tables = get_tables(db)
      vecs   = get_vec_tables(db)
      {
        "path"             => @db_path,
        "tables"           => tables.map { |t| t["name"] },
        "vec_tables"       => vecs,
        "suggested_config" => build_suggested_config(tables, vecs)
      }
    ensure
      db&.close
    end

    private

    def open_db
      db = SQLite3::Database.new(@db_path, readonly: true)
      db.results_as_hash = true
      db.enable_load_extension(true)
      SqliteVec.load(db)
      db.enable_load_extension(false)
      db
    end

    def get_tables(db)
      db.execute(
        "SELECT name, sql FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
      )
    end

    def get_vec_tables(db)
      rows = db.execute(
        "SELECT name, sql FROM sqlite_master WHERE type='table' AND sql LIKE '%vec0%'"
      )
      rows.map do |row|
        cols          = parse_vec_columns(row["sql"])
        embedding_col = cols.find { |c| c =~ /FLOAT\[/i }&.split(/\s+/)&.first
        aux_col_names = cols
          .reject { |c| c =~ /FLOAT\[/i }
          .map    { |c| c.strip.split(/\s+/).first }
          .compact + ["distance"]
        {
          "name"              => row["name"],
          "embedding_column"  => embedding_col,
          "auxiliary_columns" => aux_col_names
        }
      end
    end

    def parse_vec_columns(sql)
      m = sql.match(/\((.+)\)\s*$/m)
      return [] unless m
      m[1].split(",").map(&:strip)
    end

    def build_suggested_config(tables, vec_tables)
      config = { "description" => "" }
      return config if vec_tables.empty?

      vec      = vec_tables.first
      join_key = vec["auxiliary_columns"].reject { |c| c == "distance" }.first

      content_t = tables.find do |t|
        name = t["name"]
        sql  = t["sql"].to_s
        !name.end_with?("_vec") &&
          !name.end_with?("_fts") &&
          name != "_sqlite_mcp_meta" &&
          sql.include?("content")
      end

      if content_t
        config["semantic_search"] = {
          "vec_table"      => vec["name"],
          "content_table"  => content_t["name"],
          "content_column" => "content",
          "source_column"  => "source",
          "join_key"       => join_key
        }
      end

      config
    end
  end
end
