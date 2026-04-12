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

  # --- prefilled 引数サポート ---

  def test_analyze_prefilled_populates_resolved_hints
    result = @analyzer.analyze('最新記事', { from_date: '2026-04-06', to_date: '2026-04-12' })
    assert_equal '2026-04-06', result.resolved_hints[:from_date]
    assert_equal '2026-04-12', result.resolved_hints[:to_date]
  end

  def test_analyze_prefilled_wins_over_keyword_match
    result = @analyzer.analyze('PicoRubyの記事', { source: 'override_value' })
    assert_equal 'override_value', result.resolved_hints[:source]
  end

  def test_analyze_prefilled_empty_behaves_like_no_arg
    result_with_empty = @analyzer.analyze('PicoRubyの記事', {})
    result_without = @analyzer.analyze('PicoRubyの記事')
    assert_equal result_without.resolved_hints, result_with_empty.resolved_hints
    assert_equal result_without.missing_fields, result_with_empty.missing_fields
  end

  def test_analyze_prefilled_removes_field_from_missing_when_skip_if_resolved
    skip_analyzer = ChiebukuroMcp::IntentAnalyzer.new(@field_definitions, skip_if_resolved: true)
    result = skip_analyzer.analyze('最新記事', { from_date: '2026-04-06', to_date: '2026-04-12', limit: 10 })
    refute_includes result.missing_fields, :from_date
    refute_includes result.missing_fields, :to_date
    refute_includes result.missing_fields, :limit
    assert_includes result.missing_fields, :source
  end

  # --- field-level default 値サポート ---

  def test_analyze_applies_field_default_when_not_prefilled
    fields_with_default = [
      { name: :limit, type: :integer, required: true, default: 50 }
    ]
    analyzer = ChiebukuroMcp::IntentAnalyzer.new(fields_with_default, skip_if_resolved: true)
    result = analyzer.analyze('最新記事')
    assert_equal 50, result.resolved_hints[:limit]
    refute_includes result.missing_fields, :limit
  end

  def test_analyze_prefilled_wins_over_field_default
    fields_with_default = [
      { name: :limit, type: :integer, required: true, default: 50 }
    ]
    analyzer = ChiebukuroMcp::IntentAnalyzer.new(fields_with_default, skip_if_resolved: true)
    result = analyzer.analyze('最新記事', { limit: 5 })
    assert_equal 5, result.resolved_hints[:limit]
  end

  def test_analyze_keyword_match_wins_over_field_default
    fields_with_both = [
      { name: :source, type: :string, required: true,
        keywords: { 'cruby' => 'ruby/ruby' }, default: 'fallback_source' }
    ]
    analyzer = ChiebukuroMcp::IntentAnalyzer.new(fields_with_both, skip_if_resolved: true)
    result = analyzer.analyze('CRubyの記事')
    assert_equal 'ruby/ruby', result.resolved_hints[:source]
  end

  def test_analyze_field_default_used_when_no_keyword_match
    fields_with_both = [
      { name: :source, type: :string, required: true,
        keywords: { 'cruby' => 'ruby/ruby' }, default: 'fallback_source' }
    ]
    analyzer = ChiebukuroMcp::IntentAnalyzer.new(fields_with_both, skip_if_resolved: true)
    result = analyzer.analyze('無関係な文字列')
    assert_equal 'fallback_source', result.resolved_hints[:source]
  end
end
