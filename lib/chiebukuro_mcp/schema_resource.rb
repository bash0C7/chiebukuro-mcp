require 'sqlite3'
require 'sqlite_vec'
require_relative 'meta_reader'

module ChiebukuroMcp
  class SchemaResource
    def initialize(db_path)
      @db_path = db_path
    end

    def call
      meta   = MetaReader.read_all(@db_path)
      db     = open_db
      tables = read_tables(db)
      build_schema(meta, tables)
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

    def read_tables(db)
      db.execute(
        "SELECT name, sql FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
      )
    end

    def build_schema(meta, tables)
      lines = []

      unless meta[:meta_table_exists]
        lines << '⚠️ WARNING: No _sqlite_mcp_meta found for this DB.'
        lines << 'Do NOT guess table names. Use exactly the names under ## Table: below.'
        lines << ''
      end

      descriptions = meta[:descriptions]
      db_desc = descriptions['db:ruby_knowledge'] || first_db_description(descriptions)
      lines << '# Database Schema'
      lines << "## Description: #{db_desc}" if db_desc
      lines << ''

      tables.each do |t|
        name = t['name']
        lines << "## Table: #{name}"
        desc = descriptions["table:#{name}"]
        lines << "Description: #{desc}" if desc
        lines << '```sql'
        lines << t['sql']
        lines << '```'
        lines << ''
      end

      lines.join("\n")
    end

    def first_db_description(descriptions)
      key = descriptions.keys.find { |k| k.start_with?('db:') }
      key ? descriptions[key] : nil
    end
  end
end
