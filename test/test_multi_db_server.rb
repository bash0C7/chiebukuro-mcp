require_relative 'test_helper'
require_relative '../lib/chiebukuro_mcp/server'
require 'ruby_knowledge_store'
require 'tempfile'
require 'json'

class TestMultiDbServer < Test::Unit::TestCase
  def setup
    @tmpfile1 = Tempfile.new(['db1', '.db'])
    @tmpfile2 = Tempfile.new(['db2', '.db'])
    @db1_path = @tmpfile1.path
    @db2_path = @tmpfile2.path
    [@tmpfile1, @tmpfile2].each(&:close)

    migrations_dir = RubyKnowledgeStore::MIGRATIONS_DIR
    RubyKnowledgeStore::Migrator.new(@db1_path, migrations_dir: migrations_dir).run
    RubyKnowledgeStore::Migrator.new(@db2_path, migrations_dir: migrations_dir).run

    @config = {
      "databases" => {
        "db_one" => {
          "path" => @db1_path,
          "description" => "First test DB",
          "semantic_search" => {
            "vec_table" => "memories_vec",
            "content_table" => "memories",
            "content_column" => "content",
            "source_column" => "source",
            "join_key" => "memory_id"
          }
        },
        "db_two" => {
          "path" => @db2_path,
          "description" => "Second test DB — query only"
        }
      }
    }
    @embedder = StubEmbedder.new
  end

  def teardown
    @tmpfile1.unlink
    @tmpfile2.unlink
  end

  def test_build_mcp_server_returns_server
    server = ChiebukuroMcp::Server.new(config: @config, embedder: @embedder)
    mcp = server.build_mcp_server
    assert_not_nil mcp
  end

  def test_query_tools_created_for_each_db
    server = ChiebukuroMcp::Server.new(config: @config, embedder: @embedder)
    mcp = server.build_mcp_server
    tool_names = mcp.tool_classes.map(&:tool_name)
    assert_include tool_names, 'chiebukuro_query_db_one'
    assert_include tool_names, 'chiebukuro_query_db_two'
  end

  def test_semantic_search_tool_only_for_db_with_config
    server = ChiebukuroMcp::Server.new(config: @config, embedder: @embedder)
    mcp = server.build_mcp_server
    tool_names = mcp.tool_classes.map(&:tool_name)
    assert_include tool_names, 'chiebukuro_semantic_search_db_one'
    assert_not_include tool_names, 'chiebukuro_semantic_search_db_two'
  end

  def test_schema_resources_created_for_each_db
    server = ChiebukuroMcp::Server.new(config: @config, embedder: @embedder)
    mcp = server.build_mcp_server
    resource_uris = mcp.resource_list.map(&:uri)
    assert_include resource_uris, 'schema://db_one'
    assert_include resource_uris, 'schema://db_two'
  end

  def test_query_tool_executes_select
    server = ChiebukuroMcp::Server.new(config: @config, embedder: @embedder)
    mcp = server.build_mcp_server
    tool_class = mcp.tool_classes.find { |t| t.tool_name == 'chiebukuro_query_db_one' }
    response = tool_class.call(sql: 'SELECT 1 AS n', server_context: {})
    result = JSON.parse(response.content.first[:text])
    assert_equal 1, result.first['n']
  end

  def test_query_tool_rejects_insert
    server = ChiebukuroMcp::Server.new(config: @config, embedder: @embedder)
    mcp = server.build_mcp_server
    tool_class = mcp.tool_classes.find { |t| t.tool_name == 'chiebukuro_query_db_one' }
    response = tool_class.call(
      sql: 'INSERT INTO memories (content,source,content_hash,created_at) VALUES ("x","s","h","2024-01-01")',
      server_context: {}
    )
    assert response.error?
  end

  def test_description_embedded_in_tool
    server = ChiebukuroMcp::Server.new(config: @config, embedder: @embedder)
    mcp = server.build_mcp_server
    tool_class = mcp.tool_classes.find { |t| t.tool_name == 'chiebukuro_query_db_one' }
    assert_include tool_class.description, 'First test DB'
  end
end
