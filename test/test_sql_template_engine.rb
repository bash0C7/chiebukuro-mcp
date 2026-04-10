require_relative 'test_helper'
require_relative '../lib/chiebukuro_mcp/sql_template_engine'

class TestSqlTemplateEngine < Test::Unit::TestCase
  def setup
    @recipes = [
      {
        name: 'recent_articles',
        label: '最新記事',
        sql: 'SELECT content, source, created_at FROM memories WHERE source LIKE :source_like AND created_at BETWEEN :from_date AND :to_date ORDER BY created_at DESC LIMIT :limit',
        intent_keywords: ['記事', 'article']
      },
      {
        name: 'default_memories',
        label: '全件',
        sql: 'SELECT * FROM memories LIMIT :limit',
        intent_keywords: []
      }
    ]
    @engine = ChiebukuroMcp::SqlTemplateEngine.new(@recipes)
  end

  def test_build_selects_recipe_by_intent_keyword
    sql, _params = @engine.build('最新の記事', { source_like: 'picoruby/%', from_date: '2026-01-01', to_date: '2026-04-10', limit: 10 })
    assert_match(/SELECT content, source, created_at FROM memories/, sql)
  end

  def test_build_returns_positional_placeholders
    sql, params = @engine.build('最新の記事', { source_like: 'picoruby/%', from_date: '2026-01-01', to_date: '2026-04-10', limit: 10 })
    assert_match(/\?/, sql)
    refute_match(/:source_like/, sql)
    assert_equal ['picoruby/%', '2026-01-01', '2026-04-10', 10], params
  end

  def test_build_integer_limit_is_cast
    _sql, params = @engine.build('記事', { source_like: '%', from_date: '2026-01-01', to_date: '2026-04-10', limit: '5' })
    assert_equal 5, params.last
    assert params.last.is_a?(Integer)
  end

  def test_build_falls_back_to_default_recipe_when_no_match
    sql, params = @engine.build('完全無関係', { limit: 3 })
    assert_match(/SELECT \* FROM memories LIMIT \?/, sql)
    assert_equal [3], params
  end

  def test_build_raises_when_recipes_empty
    engine = ChiebukuroMcp::SqlTemplateEngine.new([])
    assert_raise(ArgumentError) do
      engine.build('foo', {})
    end
  end

  def test_build_rejects_non_select_template
    bad_engine = ChiebukuroMcp::SqlTemplateEngine.new([
      { name: 'evil', label: 'x', sql: 'DELETE FROM memories WHERE id = :id', intent_keywords: [] }
    ])
    assert_raise(ArgumentError) do
      bad_engine.build('foo', { id: 1 })
    end
  end

  def test_build_raises_when_slot_missing
    assert_raise(ArgumentError) do
      @engine.build('最新の記事', { from_date: '2026-01-01' })
    end
  end

  def test_build_accepts_with_clause_template
    engine = ChiebukuroMcp::SqlTemplateEngine.new([
      { name: 'with_recipe', label: 'withtest', sql: 'WITH n AS (SELECT :x) SELECT * FROM n', intent_keywords: [] }
    ])
    sql, params = engine.build('foo', { x: 1 })
    assert_match(/^WITH/, sql)
    assert_equal [1], params
  end
end
