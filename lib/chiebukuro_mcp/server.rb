require 'mcp'
require 'mcp/server/transports/stdio_transport'
require_relative 'query_tool'
require_relative 'schema_resource'
require_relative 'semantic_search_tool'

module ChiebukuroMcp
  class Server
    def initialize(config:, embedder:)
      @databases = config["databases"] || config[:databases]
      @embedder  = embedder
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
          name: "query_#{db_name}",
          description: "Execute a read-only SELECT query against: #{desc}",
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
          sem_tool_obj = SemanticSearchTool.new(path, embedder: @embedder)
          sem_tool_class = MCP::Tool.define(
            name: "semantic_search_#{db_name}",
            description: "Semantic similarity search (768-dim ruri-v3) against: #{desc}",
            input_schema: {
              type: 'object',
              properties: {
                query: { type: 'string',  description: 'Natural language search query' },
                limit: { type: 'integer', description: 'Number of results (default: 5)' }
              },
              required: ['query']
            }
          ) do |query:, limit: 5, **_|
            result = sem_tool_obj.call(query: query, limit: limit)
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
      end

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

      def method_missing(name, *args, &block)
        if @mcp_server.respond_to?(name)
          @mcp_server.send(name, *args, &block)
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
