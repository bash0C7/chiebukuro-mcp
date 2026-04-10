require_relative 'test_helper'
require_relative '../lib/chiebukuro_mcp/hints_resource'
require 'tempfile'
require 'sqlite3'

class TestHintsResource < Test::Unit::TestCase
  def setup
    @tmpfile = Tempfile.new(['hints', '.db'])
    @db_path = @tmpfile.path
    @tmpfile.close
    TestDbHelper.setup_db(@db_path)
  end

  def teardown
    @tmpfile.unlink
  end

  def test_call_returns_markdown_with_column_enum_values
    resource = ChiebukuroMcp::HintsResource.new(@db_path)
    md = resource.call
    assert_match(/# Column Hints/, md)
    assert_match(/memories\.source/, md)
    assert_match(/picoruby\/picoruby:trunk\/article/, md)
  end

  def test_call_returns_markdown_with_related_tables
    resource = ChiebukuroMcp::HintsResource.new(@db_path)
    md = resource.call
    assert_match(/memories_vec/, md)
  end

  def test_call_shows_no_hints_line_for_columns_without_hints_json
    resource = ChiebukuroMcp::HintsResource.new(@db_path)
    md = resource.call
    # memories.content has no hints_json in the test schema.
    assert_match(/memories\.content/, md)
    assert_match(/No additional hints/, md)
  end

  def test_call_old_schema_does_not_raise
    tmp = Tempfile.new(['old', '.db'])
    old_path = tmp.path
    tmp.close
    db = SQLite3::Database.new(old_path)
    db.execute('CREATE TABLE _sqlite_mcp_meta (object_type TEXT, object_name TEXT, description TEXT, PRIMARY KEY(object_type, object_name))')
    db.execute("INSERT INTO _sqlite_mcp_meta VALUES ('column', 'foo.bar', 'desc only')")
    db.close

    resource = ChiebukuroMcp::HintsResource.new(old_path)
    assert_nothing_raised do
      md = resource.call
      assert_match(/foo\.bar/, md)
    end
  ensure
    tmp&.unlink
  end
end
