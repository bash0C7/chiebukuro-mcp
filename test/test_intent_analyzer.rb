require_relative 'test_helper'
require_relative '../lib/chiebukuro_mcp/intent_analyzer'

class TestIntentAnalyzer < Test::Unit::TestCase
  def setup
    @field_definitions = [
      { name: :from_date, type: :date, required: true },
      { name: :to_date, type: :date, required: true },
      { name: :source, type: :string, required: true, keywords: { 'picoruby' => 'picoruby', 'cruby' => 'ruby/ruby' } },
      { name: :limit, type: :integer, required: true }
    ]
    @analyzer = ChiebukuroMcp::IntentAnalyzer.new(@field_definitions)
  end

  def test_analyze_returns_all_fields_as_missing_when_intent_empty
    result = @analyzer.analyze('')
    assert_equal [:from_date, :to_date, :source, :limit], result.missing_fields
  end

  def test_analyze_returns_resolved_hints_on_keyword_match
    result = @analyzer.analyze('PicoRubyの記事')
    assert_equal 'picoruby', result.resolved_hints[:source]
  end

  def test_analyze_resolved_hints_is_case_insensitive
    result = @analyzer.analyze('picoruby')
    assert_equal 'picoruby', result.resolved_hints[:source]
  end

  def test_analyze_no_match_returns_empty_resolved_hints
    result = @analyzer.analyze('無関係な文字列')
    assert_equal({}, result.resolved_hints)
  end

  def test_analyze_with_cruby_keyword
    result = @analyzer.analyze('CRubyの最新のコミット')
    assert_equal 'ruby/ruby', result.resolved_hints[:source]
  end

  def test_analyze_all_fields_always_missing_in_minimum_strategy
    # "全部聞き方式"：キーワードがあっても missing_fields は減らない
    result = @analyzer.analyze('CRubyの記事')
    assert_equal 4, result.missing_fields.length
  end

  def test_analyze_skip_if_resolved_removes_resolved_from_missing
    skip_analyzer = ChiebukuroMcp::IntentAnalyzer.new(@field_definitions, skip_if_resolved: true)
    result = skip_analyzer.analyze('CRubyの記事')
    refute_includes result.missing_fields, :source
    assert_includes result.missing_fields, :from_date
    assert_includes result.missing_fields, :to_date
    assert_includes result.missing_fields, :limit
    assert_equal 'ruby/ruby', result.resolved_hints[:source]
  end

  def test_analyze_skip_if_resolved_without_keyword_match_keeps_all_fields
    skip_analyzer = ChiebukuroMcp::IntentAnalyzer.new(@field_definitions, skip_if_resolved: true)
    result = skip_analyzer.analyze('無関係な文字列')
    assert_equal 4, result.missing_fields.length
  end
end
