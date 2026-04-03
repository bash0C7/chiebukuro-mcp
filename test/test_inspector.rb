require_relative 'test_helper'
require_relative '../lib/chiebukuro_mcp/inspector'
require 'ruby_knowledge_store'
require 'tempfile'
require 'sqlite3'
require 'sqlite_vec'

class TestInspector < Test::Unit::TestCase
  def setup
    @tmpfile = Tempfile.new(['inspector_test', '.db'])
    @db_path = @tmpfile.path
    @tmpfile.close
    RubyKnowledgeStore::Migrator.new(@db_path, migrations_dir: RubyKnowledgeStore::MIGRATIONS_DIR).run
  end

  def teardown
    @tmpfile.unlink
  end

  def test_inspect_returns_path
    result = ChiebukuroMcp::Inspector.new(@db_path).inspect_db
    assert_equal @db_path, result["path"]
  end

  def test_inspect_returns_tables_array
    result = ChiebukuroMcp::Inspector.new(@db_path).inspect_db
    assert_include result["tables"], "memories"
  end

  def test_inspect_detects_vec_table
    result = ChiebukuroMcp::Inspector.new(@db_path).inspect_db
    vec_names = result["vec_tables"].map { |v| v["name"] }
    assert_include vec_names, "memories_vec"
  end

  def test_inspect_vec_table_has_embedding_column
    result = ChiebukuroMcp::Inspector.new(@db_path).inspect_db
    vec = result["vec_tables"].find { |v| v["name"] == "memories_vec" }
    assert_equal "embedding", vec["embedding_column"]
  end

  def test_inspect_vec_table_auxiliary_columns_include_distance
    result = ChiebukuroMcp::Inspector.new(@db_path).inspect_db
    vec = result["vec_tables"].find { |v| v["name"] == "memories_vec" }
    assert_include vec["auxiliary_columns"], "distance"
  end

  def test_inspect_suggested_config_has_semantic_search
    result = ChiebukuroMcp::Inspector.new(@db_path).inspect_db
    assert result["suggested_config"].key?("semantic_search"),
      "semantic_search キーがあるはず"
  end

  def test_inspect_suggested_config_semantic_search_values
    result = ChiebukuroMcp::Inspector.new(@db_path).inspect_db
    sc = result["suggested_config"]["semantic_search"]
    assert_equal "memories_vec", sc["vec_table"]
    assert_equal "memories",     sc["content_table"]
    assert_equal "content",      sc["content_column"]
    assert_equal "source",       sc["source_column"]
    assert_equal "memory_id",    sc["join_key"]
  end

  def test_inspect_db_without_vec_no_semantic_search
    plain_tmpfile = Tempfile.new(['plain', '.db'])
    plain_path = plain_tmpfile.path
    plain_tmpfile.close

    db = SQLite3::Database.new(plain_path)
    db.execute("CREATE TABLE items (id INTEGER PRIMARY KEY, content TEXT)")
    db.close

    result = ChiebukuroMcp::Inspector.new(plain_path).inspect_db
    assert_not result["suggested_config"].key?("semantic_search"),
      "vec テーブルなしなら semantic_search キーはないはず"

    plain_tmpfile.unlink
  end
end
