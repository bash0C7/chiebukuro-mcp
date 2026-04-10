require_relative 'test_helper'
require_relative '../lib/chiebukuro_mcp/recipes_resource'
require 'tempfile'
require 'sqlite3'

class TestRecipesResource < Test::Unit::TestCase
  def setup
    @tmpfile = Tempfile.new(['recipes', '.db'])
    @db_path = @tmpfile.path
    @tmpfile.close
    TestDbHelper.setup_db(@db_path)
  end

  def teardown
    @tmpfile.unlink
  end

  def test_call_returns_markdown_with_recipe_label_in_heading
    resource = ChiebukuroMcp::RecipesResource.new(@db_path)
    md = resource.call
    assert_match(/# Query Recipes/, md)
    assert_match(/最新記事/, md)
  end

  def test_call_includes_sql_code_block
    resource = ChiebukuroMcp::RecipesResource.new(@db_path)
    md = resource.call
    assert_match(/```sql/, md)
    assert_match(/SELECT content/, md)
  end

  def test_call_returns_empty_message_when_no_recipes
    tmp = Tempfile.new(['empty', '.db'])
    empty_path = tmp.path
    tmp.close
    db = SQLite3::Database.new(empty_path)
    db.close

    resource = ChiebukuroMcp::RecipesResource.new(empty_path)
    md = resource.call
    assert_match(/No recipes/, md)
  ensure
    tmp&.unlink
  end

  def test_call_old_schema_does_not_raise
    tmp = Tempfile.new(['old', '.db'])
    old_path = tmp.path
    tmp.close
    db = SQLite3::Database.new(old_path)
    db.execute('CREATE TABLE _sqlite_mcp_meta (object_type TEXT, object_name TEXT, description TEXT, PRIMARY KEY(object_type, object_name))')
    db.close

    resource = ChiebukuroMcp::RecipesResource.new(old_path)
    assert_nothing_raised do
      md = resource.call
      assert_match(/No recipes/, md)
    end
  ensure
    tmp&.unlink
  end
end
