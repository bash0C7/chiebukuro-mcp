require 'sqlite3'
require 'sqlite_vec'
require 'json'

module ChiebukuroMcp
  # EXPLAIN QUERY PLAN を実行してクエリプランを返す読み取り専用ツール。
  # 入力 SQL は SELECT/WITH のみ許可。それ以外は ArgumentError。
  class ExplainQueryTool
    def initialize(db_path)
      @db_path = db_path
    end

    def call(sql:)
      validate_select!(sql)
      db = open_db
      rows = db.execute("EXPLAIN QUERY PLAN #{sql}")
      JSON.generate(rows)
    rescue SQLite3::Exception => e
      raise "SQLite error: #{e.message}"
    ensure
      db&.close
    end

    private

    def validate_select!(sql)
      normalized = sql.strip.upcase
      unless normalized.start_with?('SELECT') || normalized.start_with?('WITH')
        raise ArgumentError, 'Only SELECT queries are allowed'
      end
    end

    def open_db
      db = SQLite3::Database.new(@db_path, readonly: true)
      db.results_as_hash = true
      db.enable_load_extension(true)
      SqliteVec.load(db)
      db.enable_load_extension(false)
      db
    end
  end
end
