require_relative 'test_helper'
require_relative '../lib/chiebukuro_mcp/explain_query_tool'
require 'tempfile'
require 'json'

class TestExplainQueryTool < Test::Unit::TestCase
  def setup
    @tmpfile = Tempfile.new(['explain', '.db'])
    @db_path = @tmpfile.path
    @tmpfile.close
    TestDbHelper.setup_db(@db_path)
  end

  def teardown
    @tmpfile.unlink
  end

  def test_explain_select_returns_json_array
    tool = ChiebukuroMcp::ExplainQueryTool.new(@db_path)
    result = tool.call(sql: 'SELECT * FROM memories')
    parsed = JSON.parse(result)
    assert parsed.is_a?(Array)
    assert parsed.length > 0
  end

  def test_explain_result_rows_contain_detail_key
    tool = ChiebukuroMcp::ExplainQueryTool.new(@db_path)
    result = tool.call(sql: 'SELECT * FROM memories')
    parsed = JSON.parse(result)
    assert parsed.first.key?('detail')
  end

  def test_explain_rejects_insert
    tool = ChiebukuroMcp::ExplainQueryTool.new(@db_path)
    assert_raise(ArgumentError) do
      tool.call(sql: 'INSERT INTO memories (content, source, content_hash, created_at) VALUES (1,2,3,4)')
    end
  end

  def test_explain_rejects_drop
    tool = ChiebukuroMcp::ExplainQueryTool.new(@db_path)
    assert_raise(ArgumentError) do
      tool.call(sql: 'DROP TABLE memories')
    end
  end

  def test_explain_allows_with_clause
    tool = ChiebukuroMcp::ExplainQueryTool.new(@db_path)
    assert_nothing_raised do
      tool.call(sql: 'WITH n AS (SELECT 1) SELECT * FROM n')
    end
  end
end
