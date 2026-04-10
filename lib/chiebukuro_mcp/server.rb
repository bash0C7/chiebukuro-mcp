require 'mcp'
require 'mcp/server/transports/stdio_transport'
require_relative 'query_tool'
require_relative 'schema_resource'
require_relative 'semantic_search_tool'
require_relative 'probe_tool'
require_relative 'recipes_resource'
require_relative 'hints_resource'
require_relative 'explain_query_tool'
require_relative 'query_with_clarification_tool'
require_relative 'meta_reader'

module ChiebukuroMcp
  class Server
    DEFAULT_CLARIFICATION_FIELDS = [
      { name: :source_like, type: :string,  required: true, description: 'source カラムの LIKE パターン (例: picoruby/%)', meta_hint_key: 'memories.source' },
      { name: :from_date,   type: :date,    required: true, description: '期間の開始日 (YYYY-MM-DD)' },
      { name: :to_date,     type: :date,    required: true, description: '期間の終了日 (YYYY-MM-DD)' },
      { name: :limit,       type: :integer, required: true, description: '最大件数 (1-100 程度)' }
    ].freeze

    def initialize(config:, embedder:)
      @databases = config["databases"] || config[:databases]
      @embedder  = embedder
    end

    # DB 側の _sqlite_mcp_meta に clarification_field 行があればそれを使い、
    # なければ DEFAULT_CLARIFICATION_FIELDS にフォールバックする。
    # DB 自己記述の原則を守りつつ、未対応 DB でも動作を保つ。
    def clarification_fields_for(db_path)
      meta = MetaReader.read_all(db_path)
      fields = meta[:clarification_fields]
      return DEFAULT_CLARIFICATION_FIELDS if fields.nil? || fields.empty?

      fields
    rescue => e
      warn "[chiebukuro-mcp] failed to read clarification_fields from #{db_path}: #{e.message}"
      DEFAULT_CLARIFICATION_FIELDS
    end

    def build_mcp_server
      tools             = []
      resources         = []
      resource_handlers = {}

      @databases.each do |db_name, db_config|
        path    = db_config["path"]            || db_config[:path]
        desc    = db_config["description"]     || db_config[:description] || ""
        sem_cfg = db_config["semantic_search"] || db_config[:semantic_search]

        query_tool_obj = QueryTool.new(path)
        query_tool_class = MCP::Tool.define(
          name: "chiebukuro_query_#{db_name}",
          description: "【chiebukuro 知恵袋】#{db_name} DBへの読み取り専用 SELECT クエリを実行する。#{desc}",
          input_schema: {
            type: 'object',
            properties: {
              sql: { type: 'string', description: 'SQL SELECT statement to execute' }
            },
            required: ['sql']
          }
        ) do |sql:, **_|
          result = query_tool_obj.call(sql: sql)
          MCP::Tool::Response.new([{ type: 'text', text: result }])
        rescue ArgumentError => e
          MCP::Tool::Response.new([{ type: 'text', text: e.message }], error: true)
        rescue => e
          MCP::Tool::Response.new([{ type: 'text', text: e.message }], error: true)
        end
        tools << query_tool_class

        if sem_cfg
          sem_tool_obj = SemanticSearchTool.new(path, embedder: @embedder, sem_cfg: sem_cfg)
          sem_tool_class = MCP::Tool.define(
            name: "chiebukuro_semantic_search_#{db_name}",
            description: "【chiebukuro 知恵袋】#{db_name} DBへの意味検索（768次元 ruri-v3 ベクトル）。#{desc}",
            input_schema: {
              type: 'object',
              properties: {
                query:         { type: 'string',  description: 'Natural language search query' },
                limit:         { type: 'integer', description: 'Number of results (default: 5)' },
                source_filter: { type: 'string',  description: 'Optional regex to filter by source (e.g., "ruby/ruby:trunk" for CRuby trunk articles, "rurema" for rurema docs)' }
              },
              required: ['query']
            }
          ) do |query:, limit: 5, source_filter: nil, **_|
            result = sem_tool_obj.call(query: query, limit: limit, source_filter: source_filter)
            MCP::Tool::Response.new([{ type: 'text', text: result }])
          rescue => e
            MCP::Tool::Response.new([{ type: 'text', text: e.message }], error: true)
          end
          tools << sem_tool_class
        end

        schema_res_obj = SchemaResource.new(path)
        schema_uri     = "schema://#{db_name}"
        resources << MCP::Resource.new(
          uri:         schema_uri,
          name:        "#{db_name}_schema",
          description: "SQLite database schema for #{db_name}",
          mime_type:   'text/markdown'
        )
        resource_handlers[schema_uri] = schema_res_obj

        recipes_res_obj = RecipesResource.new(path)
        recipes_uri     = "recipes://#{db_name}"
        resources << MCP::Resource.new(
          uri:         recipes_uri,
          name:        "#{db_name}_recipes",
          description: "Typical query recipes for #{db_name}",
          mime_type:   'text/markdown'
        )
        resource_handlers[recipes_uri] = recipes_res_obj

        hints_res_obj = HintsResource.new(path)
        hints_uri     = "hints://#{db_name}"
        resources << MCP::Resource.new(
          uri:         hints_uri,
          name:        "#{db_name}_hints",
          description: "Column hints (enum values, sample values, related tables) for #{db_name}",
          mime_type:   'text/markdown'
        )
        resource_handlers[hints_uri] = hints_res_obj

        explain_tool_obj = ExplainQueryTool.new(path)
        explain_tool_class = MCP::Tool.define(
          name: "chiebukuro_explain_query_#{db_name}",
          description: "【chiebukuro 知恵袋】#{db_name} DBで EXPLAIN QUERY PLAN を実行し、SELECT クエリのプランを返す。#{desc}",
          input_schema: {
            type: 'object',
            properties: {
              sql: { type: 'string', description: 'SQL SELECT/WITH statement to explain' }
            },
            required: ['sql']
          }
        ) do |sql:, **_|
          result = explain_tool_obj.call(sql: sql)
          MCP::Tool::Response.new([{ type: 'text', text: result }])
        rescue ArgumentError => e
          MCP::Tool::Response.new([{ type: 'text', text: e.message }], error: true)
        rescue => e
          MCP::Tool::Response.new([{ type: 'text', text: e.message }], error: true)
        end
        tools << explain_tool_class

        clarify_fields = clarification_fields_for(path)
        clarify_tool_obj = QueryWithClarificationTool.new(path, field_definitions: clarify_fields)
        clarify_tool_class = MCP::Tool.define(
          name: "chiebukuro_query_with_clarification_#{db_name}",
          description: "【chiebukuro 知恵袋】#{db_name} DBへの対話型クエリ。曖昧な要求を elicitation で期間・ソース・件数に分解してユーザーに確認してから SELECT を実行する。#{desc}",
          input_schema: {
            type: 'object',
            properties: {
              intent: { type: 'string', description: '自然言語の要求 (例: 最新のRuby記事見せて)' }
            },
            required: ['intent']
          }
        ) do |intent:, server_context: nil, **_|
          result = clarify_tool_obj.call(intent: intent, server_context: server_context)
          MCP::Tool::Response.new([{ type: 'text', text: result }])
        rescue ArgumentError => e
          MCP::Tool::Response.new([{ type: 'text', text: e.message }], error: true)
        rescue => e
          MCP::Tool::Response.new([{ type: 'text', text: e.message }], error: true)
        end
        tools << clarify_tool_class
      end

      probe_tool_obj = ProbeTool.new
      probe_tool_class = MCP::Tool.define(
        name: 'chiebukuro_probe_capabilities',
        description: '【chiebukuro 知恵袋】MCP ホストが sampling と elicitation の capability を宣言しているか実地で確認する実証ツール。引数なし。',
        input_schema: { type: 'object', properties: {} }
      ) do |server_context: nil, **_|
        result = probe_tool_obj.call(server_context: server_context)
        MCP::Tool::Response.new([{ type: 'text', text: result }])
      rescue => e
        MCP::Tool::Response.new([{ type: 'text', text: e.message }], error: true)
      end
      tools << probe_tool_class

      mcp_server = MCP::Server.new(
        name:      'chiebukuro-mcp',
        version:   '0.1.0',
        tools:     tools,
        resources: resources
      )

      mcp_server.resources_read_handler do |params|
        uri     = params[:uri]
        handler = resource_handlers[uri]
        next [] unless handler
        content = handler.call
        [{ uri: uri, mimeType: 'text/markdown', text: content }]
      end

      ServerFacade.new(mcp_server, tools, resources)
    end

    # MCP::Server のラッパー。テストが期待する tool_classes/resource_list インターフェースを提供する。
    class ServerFacade
      def initialize(mcp_server, tools, resources)
        @mcp_server    = mcp_server
        @tool_classes  = tools
        @resource_list = resources
      end

      # ツールクラスの配列を返す（テストが .tool_name を呼べるように）
      def tool_classes
        @tool_classes
      end

      def resource_list
        @resource_list
      end

      # MCP::Server の他のメソッドへの委譲
      def respond_to_missing?(name, include_private = false)
        @mcp_server.respond_to?(name, include_private) || super
      end

      def method_missing(name, *args, **kwargs, &block)
        if @mcp_server.respond_to?(name)
          @mcp_server.send(name, *args, **kwargs, &block)
        else
          super
        end
      end
    end

    def run
      server    = build_mcp_server
      transport = MCP::Server::Transports::StdioTransport.new(server)
      transport.open
    end
  end
end
