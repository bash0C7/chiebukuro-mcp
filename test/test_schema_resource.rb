require_relative 'test_helper'
require_relative '../lib/chiebukuro_mcp/schema_resource'
require 'tempfile'
require 'sqlite3'
require 'sqlite_vec'

class TestSchemaResource < Test::Unit::TestCase
  def setup
    @tmpfile = Tempfile.new(['schema_test', '.db'])
    @db_path = @tmpfile.path
    @tmpfile.close
    TestDbHelper.setup_db(@db_path)
  end

  def teardown
    @tmpfile.unlink
  end

  def test_call_includes_warning_when_no_meta_table
    tmp = Tempfile.new(['no_meta', '.db'])
    path = tmp.path
    tmp.close
    db = SQLite3::Database.new(path)
    db.enable_load_extension(true)
    SqliteVec.load(db)
    db.enable_load_extension(false)
    db.execute('CREATE TABLE some_table(id INTEGER PRIMARY KEY, name TEXT)')
    db.close

    result = ChiebukuroMcp::SchemaResource.new(path).call
    assert_match(/⚠️ WARNING: No _sqlite_mcp_meta found/, result)
    assert_match(/Do NOT guess table names/, result)
  ensure
    tmp&.unlink
  end

  def test_call_does_not_include_warning_when_meta_table_present
    result = ChiebukuroMcp::SchemaResource.new(@db_path).call
    refute_match(/⚠️ WARNING/, result)
  end

  def test_call_includes_table_names_regardless_of_meta
    tmp = Tempfile.new(['no_meta2', '.db'])
    path = tmp.path
    tmp.close
    db = SQLite3::Database.new(path)
    db.enable_load_extension(true)
    SqliteVec.load(db)
    db.enable_load_extension(false)
    db.execute('CREATE TABLE some_table(id INTEGER PRIMARY KEY, name TEXT)')
    db.close

    result = ChiebukuroMcp::SchemaResource.new(path).call
    assert_match(/## Table: some_table/, result)
  ensure
    tmp&.unlink
  end
end
