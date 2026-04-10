require 'json'
require 'sqlite3'
require 'sqlite_vec'
require_relative 'meta_reader'
require_relative 'intent_analyzer'
require_relative 'clarification_form_builder'
require_relative 'sql_template_engine'

module ChiebukuroMcp
  # QueryWithClarificationTool — chiebukuro の対話型クエリツール。
  #
  # フロー:
  #   1. intent を受け取る
  #   2. MetaReader から recipes / hints を読む
  #   3. IntentAnalyzer で「何が未指定か」「キーワードヒット」を解析
  #   4. ClarificationFormBuilder で elicitation 用 JSON Schema を生成
  #   5. server_context.create_elicitation でユーザーに聞く
  #   6. accept → SqlTemplateEngine で SQL 構築 → DB 実行 → 結果返却
  #   7. decline/cancel → その旨を返す
  class QueryWithClarificationTool
    def initialize(db_path, field_definitions:, skip_if_resolved: true)
      @db_path = db_path
      @field_definitions = field_definitions
      @analyzer = IntentAnalyzer.new(field_definitions, skip_if_resolved: skip_if_resolved)
      @form_builder = ClarificationFormBuilder.new(field_definitions)
    end

    def call(intent:, server_context:)
      raise ArgumentError, 'server_context is required' unless server_context

      meta = MetaReader.read_all(@db_path)
      analysis = @analyzer.analyze(intent)
      schema = @form_builder.build(analysis.missing_fields, analysis.resolved_hints, meta[:hints])

      response = server_context.create_elicitation(
        message: build_prompt_message(intent),
        requested_schema: schema
      )

      action = response[:action] || response['action']
      case action
      when 'accept'
        content = normalize_content(response[:content] || response['content'])
        execute_query(intent, content, meta[:recipes])
      when 'decline'
        JSON.generate(action: 'decline', message: 'clarification declined by user. no query executed.')
      when 'cancel'
        JSON.generate(action: 'cancel', message: 'clarification cancelled. no query executed.')
      else
        JSON.generate(action: action, message: 'unexpected elicitation action')
      end
    end

    private

    def build_prompt_message(intent)
      "chiebukuro: 「#{intent}」のクエリ条件を確定させてください"
    end

    def normalize_content(content)
      return {} unless content.is_a?(Hash)

      content.each_with_object({}) { |(k, v), h| h[k.to_sym] = v }
    end

    def execute_query(intent, content, recipes)
      engine = SqlTemplateEngine.new(recipes_with_keywords(recipes))
      sql, params = engine.build(intent, content)
      rows = run_sql(sql, params)
      JSON.generate(action: 'accept', sql: sql, params: params, rows: rows)
    end

    # MetaReader が返す recipe に intent_keywords が無い場合は空配列を補う。
    # recipe の label/name をキーワードとしても利用する（緩いマッチ）。
    def recipes_with_keywords(recipes)
      recipes.map do |r|
        r.merge(
          intent_keywords: Array(r[:intent_keywords]) + [r[:label], r[:name]].compact
        )
      end
    end

    def run_sql(sql, params)
      db = open_db
      db.execute(sql, params)
    rescue SQLite3::Exception => e
      raise "SQLite error: #{e.message}"
    ensure
      db&.close
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
