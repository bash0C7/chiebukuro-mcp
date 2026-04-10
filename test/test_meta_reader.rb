require_relative 'test_helper'
require_relative '../lib/chiebukuro_mcp/meta_reader'
require 'tempfile'
require 'sqlite3'

class TestMetaReader < Test::Unit::TestCase
  def setup
    @tmpfile = Tempfile.new(['meta', '.db'])
    @db_path = @tmpfile.path
    @tmpfile.close
    TestDbHelper.setup_db(@db_path)
  end

  def teardown
    @tmpfile.unlink
  end

  # --- read_all (class method) ---

  def test_read_all_returns_descriptions_hints_recipes_keys
    result = ChiebukuroMcp::MetaReader.read_all(@db_path)
    assert result.key?(:descriptions)
    assert result.key?(:hints)
    assert result.key?(:recipes)
  end

  def test_read_all_descriptions_contain_table_entries
    result = ChiebukuroMcp::MetaReader.read_all(@db_path)
    assert_not_nil result[:descriptions]['table:memories']
    assert_match(/ナレッジ本体/, result[:descriptions]['table:memories'])
  end

  def test_read_all_hints_parsed_from_json
    result = ChiebukuroMcp::MetaReader.read_all(@db_path)
    source_hints = result[:hints]['column:memories.source']
    assert_not_nil source_hints
    assert_equal ['picoruby/picoruby:trunk/article', 'ruby/ruby:trunk/diff', 'mruby/mruby:trunk/diff'],
                 source_hints[:enum_values]
    assert_equal ['memories_vec'], source_hints[:related_tables]
  end

  def test_read_all_recipes_include_label_and_sql
    result = ChiebukuroMcp::MetaReader.read_all(@db_path)
    assert_equal 1, result[:recipes].length
    recipe = result[:recipes].first
    assert_equal 'recent_articles', recipe[:name]
    assert_equal '最新記事', recipe[:label]
    assert_match(/SELECT content/, recipe[:sql])
  end

  def test_read_all_tolerates_old_schema_without_extension_columns
    # Build a DB with only the original 3 columns.
    tmp = Tempfile.new(['old', '.db'])
    old_path = tmp.path
    tmp.close
    db = SQLite3::Database.new(old_path)
    db.execute('CREATE TABLE _sqlite_mcp_meta (object_type TEXT, object_name TEXT, description TEXT, PRIMARY KEY(object_type, object_name))')
    db.execute("INSERT INTO _sqlite_mcp_meta VALUES ('table', 'foo', 'desc')")
    db.close

    result = ChiebukuroMcp::MetaReader.read_all(old_path)
    assert_equal 'desc', result[:descriptions]['table:foo']
    assert_equal({}, result[:hints])
    assert_equal [], result[:recipes]
  ensure
    tmp&.unlink
  end

  def test_read_all_tolerates_missing_meta_table
    tmp = Tempfile.new(['empty', '.db'])
    empty_path = tmp.path
    tmp.close
    db = SQLite3::Database.new(empty_path)
    db.execute('CREATE TABLE irrelevant(x)')
    db.close

    result = ChiebukuroMcp::MetaReader.read_all(empty_path)
    assert_equal({}, result[:descriptions])
    assert_equal({}, result[:hints])
    assert_equal [], result[:recipes]
  ensure
    tmp&.unlink
  end

  # --- instance API (used by QueryWithClarificationTool side) ---

  def test_instance_column_hints_returns_enum_values
    reader = ChiebukuroMcp::MetaReader.new(@db_path)
    hints = reader.column_hints('memories.source')
    assert_equal ['picoruby/picoruby:trunk/article', 'ruby/ruby:trunk/diff', 'mruby/mruby:trunk/diff'],
                 hints[:enum_values]
  end

  def test_instance_column_hints_returns_empty_hash_for_unknown_column
    reader = ChiebukuroMcp::MetaReader.new(@db_path)
    assert_equal({}, reader.column_hints('memories.unknown'))
  end

  def test_instance_recipes_returns_array
    reader = ChiebukuroMcp::MetaReader.new(@db_path)
    recipes = reader.recipes
    assert_equal 1, recipes.length
    assert_equal 'recent_articles', recipes.first[:name]
  end

  def test_instance_column_meta_returns_description
    reader = ChiebukuroMcp::MetaReader.new(@db_path)
    assert_match(/ソース識別子/, reader.column_meta('memories.source'))
  end

  def test_instance_column_meta_returns_nil_for_unknown_column
    reader = ChiebukuroMcp::MetaReader.new(@db_path)
    assert_nil reader.column_meta('memories.unknown')
  end

  # --- clarification_fields ---

  def test_read_all_returns_clarification_fields_key
    result = ChiebukuroMcp::MetaReader.read_all(@db_path)
    assert result.key?(:clarification_fields)
    assert result[:clarification_fields].is_a?(Array)
  end

  def test_clarification_fields_are_ordered_by_order_attribute
    result = ChiebukuroMcp::MetaReader.read_all(@db_path)
    fields = result[:clarification_fields]
    names = fields.map { |f| f[:name] }
    assert_equal [:source_like, :from_date, :to_date, :limit], names
  end

  def test_clarification_field_parses_required_and_type
    result = ChiebukuroMcp::MetaReader.read_all(@db_path)
    source_field = result[:clarification_fields].find { |f| f[:name] == :source_like }
    assert_equal :string, source_field[:type]
    assert_equal true, source_field[:required]
  end

  def test_clarification_field_parses_keywords_map
    result = ChiebukuroMcp::MetaReader.read_all(@db_path)
    source_field = result[:clarification_fields].find { |f| f[:name] == :source_like }
    assert_equal 'ruby/ruby:trunk/%', source_field[:keywords]['CRuby']
    assert_equal 'picoruby/picoruby:trunk/%', source_field[:keywords]['PicoRuby']
  end

  def test_clarification_field_carries_description
    result = ChiebukuroMcp::MetaReader.read_all(@db_path)
    from_field = result[:clarification_fields].find { |f| f[:name] == :from_date }
    assert_match(/開始日/, from_field[:description])
  end

  def test_clarification_fields_empty_on_old_schema
    tmp = Tempfile.new(['old2', '.db'])
    old_path = tmp.path
    tmp.close
    db = SQLite3::Database.new(old_path)
    db.execute('CREATE TABLE _sqlite_mcp_meta (object_type TEXT, object_name TEXT, description TEXT, PRIMARY KEY(object_type, object_name))')
    db.close
    result = ChiebukuroMcp::MetaReader.read_all(old_path)
    assert_equal [], result[:clarification_fields]
  ensure
    tmp&.unlink
  end
end
