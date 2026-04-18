require_relative 'test_helper'
require_relative '../lib/chiebukuro_mcp/server'
require 'tempfile'
require 'json'
require 'stringio'

class TestMultiDbServer < Test::Unit::TestCase
  def setup
    @tmpfile1 = Tempfile.new(['db1', '.db'])
    @tmpfile2 = Tempfile.new(['db2', '.db'])
    @db1_path = @tmpfile1.path
    @db2_path = @tmpfile2.path
    [@tmpfile1, @tmpfile2].each(&:close)

    TestDbHelper.setup_db(@db1_path)
    TestDbHelper.setup_db(@db2_path)

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

  def test_probe_capabilities_tool_registered
    server = ChiebukuroMcp::Server.new(config: @config, embedder: @embedder)
    mcp = server.build_mcp_server
    tool_names = mcp.tool_classes.map(&:tool_name)
    assert_include tool_names, 'chiebukuro_probe_capabilities'
  end

  def test_recipes_resources_created_for_each_db
    server = ChiebukuroMcp::Server.new(config: @config, embedder: @embedder)
    mcp = server.build_mcp_server
    uris = mcp.resource_list.map(&:uri)
    assert_include uris, 'recipes://db_one'
    assert_include uris, 'recipes://db_two'
  end

  def test_hints_resources_created_for_each_db
    server = ChiebukuroMcp::Server.new(config: @config, embedder: @embedder)
    mcp = server.build_mcp_server
    uris = mcp.resource_list.map(&:uri)
    assert_include uris, 'hints://db_one'
    assert_include uris, 'hints://db_two'
  end

  def test_explain_query_tools_created_for_each_db
    server = ChiebukuroMcp::Server.new(config: @config, embedder: @embedder)
    mcp = server.build_mcp_server
    tool_names = mcp.tool_classes.map(&:tool_name)
    assert_include tool_names, 'chiebukuro_explain_query_db_one'
    assert_include tool_names, 'chiebukuro_explain_query_db_two'
  end

  def test_query_with_clarification_tools_created_for_each_db
    server = ChiebukuroMcp::Server.new(config: @config, embedder: @embedder)
    mcp = server.build_mcp_server
    tool_names = mcp.tool_classes.map(&:tool_name)
    assert_include tool_names, 'chiebukuro_query_with_clarification_db_one'
    assert_include tool_names, 'chiebukuro_query_with_clarification_db_two'
  end

  def test_clarification_fields_loaded_from_db_meta
    server = ChiebukuroMcp::Server.new(config: @config, embedder: @embedder)
    fields = server.clarification_fields_for(@db1_path)
    names = fields.map { |f| f[:name] }
    assert_includes names, :source_like
    assert_includes names, :from_date
    assert_includes names, :to_date
    assert_includes names, :limit

    source_field = fields.find { |f| f[:name] == :source_like }
    assert_equal 'ruby/ruby:trunk/%', source_field[:keywords]['CRuby']
    assert_includes source_field[:enum_values], 'picoruby/picoruby:trunk/%'
  end

  def test_clarification_fields_fallback_to_default_when_db_has_no_meta
    tmp = Tempfile.new(['empty', '.db'])
    empty_path = tmp.path
    tmp.close
    db = SQLite3::Database.new(empty_path)
    db.execute('CREATE TABLE irrelevant(x)')
    db.close

    server = ChiebukuroMcp::Server.new(config: @config, embedder: @embedder)
    fields = server.clarification_fields_for(empty_path)
    assert_equal ChiebukuroMcp::Server::DEFAULT_CLARIFICATION_FIELDS, fields
  ensure
    tmp&.unlink
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

  def test_clarify_tool_schema_includes_all_clarification_fields_as_optional
    server = ChiebukuroMcp::Server.new(config: @config, embedder: @embedder)
    mcp = server.build_mcp_server
    clarify_tool_class = mcp.tool_classes.find { |t| t.tool_name == 'chiebukuro_query_with_clarification_db_one' }
    refute_nil clarify_tool_class, 'clarify tool class must exist'

    schema = clarify_tool_class.input_schema
    schema_hash = schema.respond_to?(:to_h) ? schema.to_h : schema
    props = schema_hash[:properties] || schema_hash['properties']
    required = schema_hash[:required] || schema_hash['required']

    # intent は required、他は optional として存在する
    prop_keys = props.keys.map(&:to_sym)
    assert_includes prop_keys, :intent, 'intent property missing'
    assert_equal ['intent'], Array(required).map(&:to_s)

    # 各 clarification_field が top-level property として入ってる
    assert_includes prop_keys, :source_like
    assert_includes prop_keys, :from_date
    assert_includes prop_keys, :to_date
    assert_includes prop_keys, :limit
  end

  def test_clarify_tool_description_starts_with_agent_usage_hint
    server = ChiebukuroMcp::Server.new(config: @config, embedder: @embedder)
    mcp = server.build_mcp_server
    clarify_tool_class = mcp.tool_classes.find { |t| t.tool_name == 'chiebukuro_query_with_clarification_db_one' }
    refute_nil clarify_tool_class
    description = clarify_tool_class.description
    assert_match(/\A\[Agent usage\]/, description, 'description must start with [Agent usage] hint')
    assert_match(/date_from/, description)
    assert_match(/source_like/, description)
  end

  def test_clarify_tool_description_mentions_yml_defaults_policy
    server = ChiebukuroMcp::Server.new(config: @config, embedder: @embedder)
    mcp = server.build_mcp_server
    clarify_tool_class = mcp.tool_classes.find { |t| t.tool_name == 'chiebukuro_query_with_clarification_db_one' }
    description = clarify_tool_class.description
    # Agents should be told not to pre-fill slots that have yml defaults,
    # unless the user explicitly asked for something different.
    assert_match(/default/, description)
    assert_match(/limit/, description)
  end

  def test_clarify_tool_schema_date_field_has_date_format
    server = ChiebukuroMcp::Server.new(config: @config, embedder: @embedder)
    mcp = server.build_mcp_server
    clarify_tool_class = mcp.tool_classes.find { |t| t.tool_name == 'chiebukuro_query_with_clarification_db_one' }
    schema_hash = clarify_tool_class.input_schema
    schema_hash = schema_hash.to_h if schema_hash.respond_to?(:to_h)
    props = schema_hash[:properties] || schema_hash['properties']
    from_date_prop = props[:from_date] || props['from_date']
    assert_equal 'string', (from_date_prop[:type] || from_date_prop['type'])
    assert_equal 'date', (from_date_prop[:format] || from_date_prop['format'])
  end

  def test_warns_when_db_has_no_recipes_and_no_clarification_fields
    tmp = Tempfile.new(['empty_meta_table', '.sqlite3'])
    path = tmp.path
    tmp.close
    db = SQLite3::Database.new(path)
    db.execute(<<~SQL)
      CREATE TABLE _sqlite_mcp_meta (
        object_type TEXT NOT NULL,
        object_name TEXT NOT NULL,
        description TEXT,
        hints_json TEXT,
        recipe_sql TEXT,
        recipe_label TEXT,
        PRIMARY KEY (object_type, object_name)
      )
    SQL
    db.close

    config = { 'databases' => { 'empty_db' => { 'path' => path, 'description' => 'x' } } }
    server = ChiebukuroMcp::Server.new(config: config, embedder: @embedder)

    captured = capture_stderr { server.build_mcp_server }
    assert_match(/empty_db.*no recipes.*clarification_fields/, captured)
  ensure
    tmp&.unlink
  end

  def test_warns_table_not_found_when_no_meta_table
    tmp = Tempfile.new(['no_meta_db', '.sqlite3'])
    path = tmp.path
    tmp.close
    db = SQLite3::Database.new(path)
    db.execute('CREATE TABLE noop (id INTEGER)')
    db.close

    config = { 'databases' => { 'no_meta_db' => { 'path' => path, 'description' => 'x' } } }
    server = ChiebukuroMcp::Server.new(config: config, embedder: @embedder)

    captured = capture_stderr { server.build_mcp_server }
    assert_match(/_sqlite_mcp_meta table not found/, captured)
    assert_match(/apply_meta_patches\.rb no_meta_db/, captured)
  ensure
    tmp&.unlink
  end

  def test_warns_empty_recipes_separately_when_meta_table_exists_but_empty
    tmp = Tempfile.new(['empty_meta_db', '.sqlite3'])
    path = tmp.path
    tmp.close
    db = SQLite3::Database.new(path)
    db.execute(<<~SQL)
      CREATE TABLE _sqlite_mcp_meta (
        object_type TEXT NOT NULL,
        object_name TEXT NOT NULL,
        description TEXT,
        hints_json TEXT,
        recipe_sql TEXT,
        recipe_label TEXT,
        PRIMARY KEY (object_type, object_name)
      )
    SQL
    db.close

    config = { 'databases' => { 'empty_meta_db' => { 'path' => path, 'description' => 'x' } } }
    server = ChiebukuroMcp::Server.new(config: config, embedder: @embedder)

    captured = capture_stderr { server.build_mcp_server }
    assert_match(/no recipes.*clarification_fields/, captured)
    refute_match(/_sqlite_mcp_meta table not found/, captured)
  ensure
    tmp&.unlink
  end

  def test_query_tool_emits_structured_json_log_to_stderr
    server = ChiebukuroMcp::Server.new(config: @config, embedder: @embedder)
    mcp    = server.build_mcp_server
    query_tool = mcp.tool_classes.find { |t| t.tool_name == 'chiebukuro_query_db_one' }

    captured = capture_stderr do
      query_tool.call(sql: "SELECT 1", server_context: nil)
    end

    json_line = captured.lines.find { |l| l.start_with?('{') }
    assert_not_nil json_line, "期待: JSON ログ行が stderr に出る / 実際の stderr:\n#{captured}"

    entry = JSON.parse(json_line)
    assert_equal 'tool_call',              entry['kind']
    assert_equal 'chiebukuro_query_db_one', entry['tool']
    assert_equal 'db_one',                 entry['db']
    assert_kind_of Integer,                entry['elapsed_ms']
    assert_kind_of Integer,                entry['result_rows']
    assert_match(/\A\d{4}-\d{2}-\d{2}T/,   entry['ts'])
  end

  def test_semantic_search_tool_emits_structured_json_log
    server = ChiebukuroMcp::Server.new(config: @config, embedder: @embedder)
    mcp    = server.build_mcp_server
    sem_tool = mcp.tool_classes.find { |t| t.tool_name == 'chiebukuro_semantic_search_db_one' }

    captured = capture_stderr { sem_tool.call(query: "hello", server_context: nil) }
    json_line = captured.lines.find { |l| l.start_with?('{') }
    assert_not_nil json_line
    entry = JSON.parse(json_line)
    assert_equal 'chiebukuro_semantic_search_db_one', entry['tool']
    assert_equal 'db_one',                            entry['db']
  end

  def test_explain_query_tool_emits_structured_json_log
    server = ChiebukuroMcp::Server.new(config: @config, embedder: @embedder)
    mcp    = server.build_mcp_server
    exp_tool = mcp.tool_classes.find { |t| t.tool_name == 'chiebukuro_explain_query_db_two' }

    captured = capture_stderr { exp_tool.call(sql: "SELECT 1", server_context: nil) }
    json_line = captured.lines.find { |l| l.start_with?('{') }
    assert_not_nil json_line
    entry = JSON.parse(json_line)
    assert_equal 'chiebukuro_explain_query_db_two', entry['tool']
  end

  def test_clarification_tool_emits_structured_json_log
    server = ChiebukuroMcp::Server.new(config: @config, embedder: @embedder)
    mcp    = server.build_mcp_server
    clr_tool = mcp.tool_classes.find { |t| t.tool_name == 'chiebukuro_query_with_clarification_db_two' }

    ctx = FakeServerContext.new(elicitation: :cancelled)
    captured = capture_stderr do
      clr_tool.call(intent: "test", server_context: ctx)
    end
    json_line = captured.lines.find { |l| l.start_with?('{') }
    assert_not_nil json_line
    entry = JSON.parse(json_line)
    assert_equal 'chiebukuro_query_with_clarification_db_two', entry['tool']
  end

  def test_probe_tool_emits_structured_json_log
    server = ChiebukuroMcp::Server.new(config: @config, embedder: @embedder)
    mcp    = server.build_mcp_server
    probe_tool = mcp.tool_classes.find { |t| t.tool_name == 'chiebukuro_probe_capabilities' }

    ctx = FakeServerContext.new
    captured = capture_stderr { probe_tool.call(server_context: ctx) }
    json_line = captured.lines.find { |l| l.start_with?('{') }
    assert_not_nil json_line
    entry = JSON.parse(json_line)
    assert_equal 'chiebukuro_probe_capabilities', entry['tool']
    assert_equal '-',                             entry['db']  # DB-independent tools use "-"
  end

  def test_human_warning_and_json_log_coexist_on_startup_and_call
    # meta 欠損 DB を作り、起動時 warn + tool 呼び出しによる JSON ログの両方が出ることを確認
    tmp = Tempfile.new(['no_meta', '.sqlite3'])
    path = tmp.path
    tmp.close
    db = SQLite3::Database.new(path)
    db.execute('CREATE TABLE noop (id INTEGER)')
    db.close

    config = { 'databases' => { 'no_meta_db' => { 'path' => path, 'description' => 'x' } } }
    server = ChiebukuroMcp::Server.new(config: config, embedder: @embedder)

    mcp = nil
    captured_startup = capture_stderr { mcp = server.build_mcp_server }
    assert_match(/\A\[chiebukuro-mcp\]/, captured_startup.lines.first)  # human starts with `[`
    refute_match(/^\{/, captured_startup)                                # no JSON at startup

    query_tool = mcp.tool_classes.find { |t| t.tool_name == 'chiebukuro_query_no_meta_db' }
    captured_call = capture_stderr { query_tool.call(sql: "SELECT 1", server_context: nil) }
    json_line = captured_call.lines.find { |l| l.start_with?('{') }
    assert_not_nil json_line, "expected JSON log on tool call"
    assert_equal 'tool_call', JSON.parse(json_line)['kind']
  ensure
    tmp&.unlink
  end

  private

  def capture_stderr
    original = $stderr
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = original
  end
end
