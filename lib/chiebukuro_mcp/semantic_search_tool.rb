require 'sqlite3'
require 'sqlite_vec'
require 'json'

module ChiebukuroMcp
  class SemanticSearchTool
    DEFAULT_SEM_CFG = {
      "vec_table"      => "memories_vec",
      "content_table"  => "memories",
      "content_column" => "content",
      "source_column"  => "source",
      "join_key"       => "memory_id"
    }.freeze

    def initialize(db_path, embedder:, sem_cfg: nil)
      @db_path  = db_path
      @embedder = embedder
      cfg = DEFAULT_SEM_CFG.merge(sem_cfg || {})
      @vec_table      = cfg["vec_table"]
      @content_table  = cfg["content_table"]
      @content_column = cfg["content_column"]
      @source_column  = cfg["source_column"]
      @join_key       = cfg["join_key"]
    end

    def call(query:, limit: 5, source_filter: nil)
      embedding = @embedder.embed(query)
      blob = embedding.pack('f*')
      fetch_limit = source_filter ? limit * 3 : limit
      db = open_db
      rows = db.execute(
        "SELECT m.#{@content_column}, m.#{@source_column}, v.distance
         FROM #{@vec_table} v
         JOIN #{@content_table} m ON m.id = v.#{@join_key}
         WHERE v.embedding MATCH ? AND k = ?
         ORDER BY v.distance",
        [blob, fetch_limit]
      )
      results = rows.map { |r|
        { 'content' => r[@content_column], 'source' => r[@source_column], 'distance' => r['distance'] }
      }
      if source_filter
        pattern = Regexp.new(source_filter)
        results = results.select { |r| r['source'].match?(pattern) }
      end
      JSON.generate(results.first(limit))
    rescue SQLite3::Exception => e
      raise "SQLite error: #{e.message}"
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
  end
end
