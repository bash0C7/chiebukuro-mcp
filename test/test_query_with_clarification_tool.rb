require_relative 'test_helper'
require_relative '../lib/chiebukuro_mcp/query_with_clarification_tool'
require_relative '../lib/chiebukuro_mcp/server'
require 'tempfile'
require 'json'

class TestQueryWithClarificationTool < Test::Unit::TestCase
  DEFAULT_FIELDS = [
    { name: :source_like, type: :string,  required: true, description: 'source LIKE パターン' },
    { name: :from_date,   type: :date,    required: true, description: '開始日' },
    { name: :to_date,     type: :date,    required: true, description: '終了日' },
    { name: :limit,       type: :integer, required: true, description: '最大件数' }
  ].freeze

  def setup
    @tmpfile = Tempfile.new(['clarify', '.db'])
    @db_path = @tmpfile.path
    @tmpfile.close
    TestDbHelper.setup_db(@db_path)

    # insert a couple of rows so SELECT returns something
    embedder = StubEmbedder.new
    TestDbHelper.insert_memory(@db_path, 'content-a', 'picoruby/picoruby:trunk/article', embedder)
    TestDbHelper.insert_memory(@db_path, 'content-b', 'ruby/ruby:trunk/diff', embedder)
  end

  def teardown
    @tmpfile.unlink
  end

  def make_tool
    ChiebukuroMcp::QueryWithClarificationTool.new(@db_path, field_definitions: DEFAULT_FIELDS)
  end

  def test_raises_when_server_context_nil
    tool = make_tool
    assert_raise(ArgumentError) do
      tool.call(intent: '最新記事', server_context: nil)
    end
  end

  def test_accept_runs_query_and_returns_json_result
    ctx = FakeServerContext.new(
      elicitation: :supported,
      elicitation_content: {
        source_like: 'picoruby%',
        from_date: '2020-01-01',
        to_date: '2099-12-31',
        limit: 10
      }
    )
    tool = make_tool
    result = tool.call(intent: '最新記事', server_context: ctx)
    parsed = JSON.parse(result)
    assert parsed.is_a?(Hash), 'expected wrapper hash response'
    assert parsed.key?('rows')
    assert parsed['rows'].is_a?(Array)
    assert_equal 'accept', parsed['action']
  end

  def test_decline_returns_decline_message
    ctx = FakeServerContext.new(elicitation: :declined)
    tool = make_tool
    result = tool.call(intent: '最新記事', server_context: ctx)
    parsed = JSON.parse(result)
    assert_equal 'decline', parsed['action']
    refute parsed.key?('rows')
  end

  def test_cancel_returns_cancel_message
    ctx = FakeServerContext.new(elicitation: :cancelled)
    tool = make_tool
    result = tool.call(intent: '最新記事', server_context: ctx)
    parsed = JSON.parse(result)
    assert_equal 'cancel', parsed['action']
  end

  def test_elicitation_unsupported_raises
    ctx = FakeServerContext.new(elicitation: :unsupported)
    tool = make_tool
    assert_raise(RuntimeError) do
      tool.call(intent: '最新記事', server_context: ctx)
    end
  end

  def test_elicitation_form_schema_includes_all_required_fields
    ctx = FakeServerContext.new(
      elicitation: :supported,
      elicitation_content: {
        source_like: '%',
        from_date: '2020-01-01',
        to_date: '2099-12-31',
        limit: 5
      }
    )
    tool = make_tool
    tool.call(intent: '最新記事', server_context: ctx)
    form_call = ctx.last_elicitation_call
    schema = form_call[:requested_schema]
    assert_equal 'object', schema[:type]
    assert schema[:properties].key?(:source_like)
    assert schema[:properties].key?(:from_date)
    assert schema[:properties].key?(:to_date)
    assert schema[:properties].key?(:limit)
  end

  def test_accept_result_contains_recipe_sql
    ctx = FakeServerContext.new(
      elicitation: :supported,
      elicitation_content: {
        source_like: '%',
        from_date: '2020-01-01',
        to_date: '2099-12-31',
        limit: 5
      }
    )
    tool = make_tool
    result = tool.call(intent: '最新記事', server_context: ctx)
    parsed = JSON.parse(result)
    assert_match(/SELECT/, parsed['sql'])
  end

  def test_fallback_when_recipes_empty
    require 'tempfile'
    file = Tempfile.new(['empty_db', '.sqlite3'])
    file.close
    db = SQLite3::Database.new(file.path)
    db.execute('CREATE TABLE noop (id INTEGER)')
    db.close
    db_path = file.path

    tool = ChiebukuroMcp::QueryWithClarificationTool.new(
      db_path,
      field_definitions: ChiebukuroMcp::Server::DEFAULT_CLARIFICATION_FIELDS
    )
    fake_ctx = Object.new
    def fake_ctx.create_elicitation(**_); raise 'should not elicit'; end

    result_json = tool.call(intent: 'find something', server_context: fake_ctx)
    result = JSON.parse(result_json)

    assert_equal 'fallback', result['action']
    assert_match(/no pre-defined recipe/, result['message'])
    assert_match(/chiebukuro_query_/, result['message'])
  end

  # Regression: when a field is resolved from the intent (e.g. source_like
  # from "CRuby"), the tool must merge resolved_hints into the accept
  # content before calling SqlTemplateEngine, otherwise the slot will be
  # missing from the form payload and substitution raises ArgumentError.
  def test_accept_merges_resolved_hints_into_final_content
    keyword_fields = [
      { name: :source_like, type: :string,  required: true, description: 'source pattern',
        keywords: { 'CRuby' => 'ruby/ruby:trunk/%' } },
      { name: :from_date,   type: :date,    required: true, description: 'start' },
      { name: :to_date,     type: :date,    required: true, description: 'end' },
      { name: :limit,       type: :integer, required: true, description: 'limit' }
    ]
    tool = ChiebukuroMcp::QueryWithClarificationTool.new(@db_path, field_definitions: keyword_fields)

    # source_like is resolved from intent and therefore NOT in elicitation_content.
    ctx = FakeServerContext.new(
      elicitation: :supported,
      elicitation_content: {
        from_date: '2020-01-01',
        to_date: '2099-12-31',
        limit: 10
      }
    )

    result = tool.call(intent: 'CRubyのtrunk変更記事', server_context: ctx)
    parsed = JSON.parse(result)
    assert_equal 'accept', parsed['action']
    assert parsed.key?('rows')
    assert_includes parsed['params'], 'ruby/ruby:trunk/%'

    # The elicitation form should have skipped the resolved field entirely.
    form_schema = ctx.last_elicitation_call[:requested_schema]
    refute form_schema[:properties].key?(:source_like), 'resolved field must be skipped from form'
  end

  # --- prefilled kwargs サポート ---

  def test_call_with_prefilled_date_populates_form_default
    ctx = FakeServerContext.new(
      elicitation: :supported,
      elicitation_content: {
        source_like: '%',
        limit: 5
      }
    )
    tool = make_tool
    tool.call(
      intent: '最近の記事',
      server_context: ctx,
      from_date: '2026-04-06',
      to_date: '2026-04-12'
    )
    form_schema = ctx.last_elicitation_call[:requested_schema]
    # from_date / to_date は skip_if_resolved で missing から落ちる
    refute form_schema[:properties].key?(:from_date), 'prefilled from_date should be skipped from form'
    refute form_schema[:properties].key?(:to_date),   'prefilled to_date should be skipped from form'
    assert form_schema[:properties].key?(:source_like), 'source_like should still be asked'
    assert form_schema[:properties].key?(:limit),       'limit should still be asked'
  end

  def test_call_prefilled_values_flow_into_sql_params
    ctx = FakeServerContext.new(
      elicitation: :supported,
      elicitation_content: {
        source_like: 'picoruby%',
        limit: 5
      }
    )
    tool = make_tool
    result = tool.call(
      intent: '最新記事',
      server_context: ctx,
      from_date: '2020-01-01',
      to_date: '2099-12-31'
    )
    parsed = JSON.parse(result)
    assert_equal 'accept', parsed['action']
    assert_includes parsed['params'], '2020-01-01'
    assert_includes parsed['params'], '2099-12-31'
    assert_includes parsed['params'], 'picoruby%'
  end
end
