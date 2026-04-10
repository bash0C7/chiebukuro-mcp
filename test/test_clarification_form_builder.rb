require_relative 'test_helper'
require_relative '../lib/chiebukuro_mcp/clarification_form_builder'

class TestClarificationFormBuilder < Test::Unit::TestCase
  def setup
    @fields = [
      { name: :from_date, type: :date,    required: true, description: '開始日' },
      { name: :to_date,   type: :date,    required: true, description: '終了日' },
      { name: :source,    type: :string,  required: true, description: 'ソース', meta_hint_key: 'memories.source' },
      { name: :limit,     type: :integer, required: true, description: '最大件数' }
    ]
    @builder = ChiebukuroMcp::ClarificationFormBuilder.new(@fields)
  end

  def test_build_returns_object_schema_with_all_missing_fields
    schema = @builder.build([:from_date, :to_date, :source, :limit], {}, {})
    assert_equal 'object', schema[:type]
    assert schema[:properties].key?(:from_date)
    assert schema[:properties].key?(:to_date)
    assert schema[:properties].key?(:source)
    assert schema[:properties].key?(:limit)
  end

  def test_build_required_matches_missing_fields
    schema = @builder.build([:from_date, :to_date], {}, {})
    assert_equal [:from_date, :to_date], schema[:required]
  end

  def test_date_field_has_format_date
    schema = @builder.build([:from_date], {}, {})
    assert_equal 'string', schema[:properties][:from_date][:type]
    assert_equal 'date', schema[:properties][:from_date][:format]
  end

  def test_integer_field_has_integer_type
    schema = @builder.build([:limit], {}, {})
    assert_equal 'integer', schema[:properties][:limit][:type]
  end

  def test_string_field_with_meta_hint_generates_oneof
    meta_hints = {
      'column:memories.source' => { enum_values: ['picoruby/picoruby:trunk/article', 'ruby/ruby:trunk/diff'] }
    }
    schema = @builder.build([:source], {}, meta_hints)
    source_prop = schema[:properties][:source]
    assert_equal 'string', source_prop[:type]
    assert_equal 2, source_prop[:oneOf].length
    assert_equal 'picoruby/picoruby:trunk/article', source_prop[:oneOf].first[:const]
  end

  def test_resolved_hints_become_defaults
    schema = @builder.build([:source], { source: 'picoruby' }, {})
    assert_equal 'picoruby', schema[:properties][:source][:default]
  end

  def test_empty_missing_fields_returns_empty_properties
    schema = @builder.build([], {}, {})
    assert_equal({}, schema[:properties])
    assert_equal [], schema[:required]
  end
end
