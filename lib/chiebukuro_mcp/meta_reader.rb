require 'sqlite3'
require 'sqlite_vec'
require 'json'

module ChiebukuroMcp
  # MetaReader は _sqlite_mcp_meta テーブルの読み取りを一箇所に集約する。
  #
  # 拡張スキーマ:
  #   object_type  — 'db' | 'table' | 'column' | 'recipe'
  #   object_name  — 対象名（column は 'table.column'、recipe は一意ラベル）
  #   description  — 人間向け説明
  #   hints_json   — column 用の補助情報（enum_values / sample_values / related_tables 等）
  #   recipe_sql   — recipe 用の SQL 本文
  #   recipe_label — recipe 用の人間向けラベル
  #
  # 旧スキーマ（hints_json / recipe_sql / recipe_label 列が無い DB）でも
  # 例外を投げずに空の結果を返す。
  class MetaReader
    EMPTY_RESULT = { descriptions: {}, hints: {}, recipes: [] }.freeze

    def self.read_all(db_path)
      db = open_db(db_path)
      return EMPTY_RESULT.dup unless meta_table_exists?(db)

      columns = meta_columns(db)
      has_hints_json = columns.include?('hints_json')
      has_recipe_sql = columns.include?('recipe_sql')

      select_cols = ['object_type', 'object_name', 'description']
      select_cols << 'hints_json' if has_hints_json
      select_cols << 'recipe_sql' if has_recipe_sql
      select_cols << 'recipe_label' if has_recipe_sql && columns.include?('recipe_label')

      rows = db.execute("SELECT #{select_cols.join(', ')} FROM _sqlite_mcp_meta")

      descriptions = {}
      hints = {}
      recipes = []

      rows.each do |row|
        type = row['object_type']
        name = row['object_name']
        key = "#{type}:#{name}"
        descriptions[key] = row['description'] if row['description']

        if type == 'column' && has_hints_json && row['hints_json']
          parsed = safe_parse_json(row['hints_json'])
          hints[key] = parsed if parsed
        end

        if type == 'recipe' && has_recipe_sql && row['recipe_sql']
          recipes << {
            name: name,
            label: row['recipe_label'],
            description: row['description'],
            sql: row['recipe_sql']
          }
        end
      end

      { descriptions: descriptions, hints: hints, recipes: recipes }
    ensure
      db&.close
    end

    def self.open_db(db_path)
      db = SQLite3::Database.new(db_path, readonly: true)
      db.results_as_hash = true
      db.enable_load_extension(true)
      SqliteVec.load(db)
      db.enable_load_extension(false)
      db
    end

    def self.meta_table_exists?(db)
      db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='_sqlite_mcp_meta'").any?
    end

    def self.meta_columns(db)
      db.execute('PRAGMA table_info(_sqlite_mcp_meta)').map { |r| r['name'] }
    end

    def self.safe_parse_json(json_str)
      parsed = JSON.parse(json_str)
      return nil unless parsed.is_a?(Hash)

      parsed.each_with_object({}) { |(k, v), h| h[k.to_sym] = v }
    rescue JSON::ParserError
      nil
    end

    # ----- Instance API -----

    def initialize(db_path)
      @db_path = db_path
      @cache = nil
    end

    def read_all
      @cache ||= self.class.read_all(@db_path)
    end

    def descriptions
      read_all[:descriptions]
    end

    def all_hints
      read_all[:hints]
    end

    def recipes
      read_all[:recipes]
    end

    # 'memories.source' のようなキーでカラムヒントを取得。
    # 見つからない場合は空 Hash を返す。
    def column_hints(column_name)
      all_hints["column:#{column_name}"] || {}
    end

    # 'memories.source' のようなキーでカラム description を取得。
    def column_meta(column_name)
      descriptions["column:#{column_name}"]
    end
  end
end
