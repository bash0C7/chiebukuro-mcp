require_relative 'test_helper'
require_relative '../lib/chiebukuro_mcp/probe_tool'
require 'json'

class TestProbeTool < Test::Unit::TestCase
  def test_reports_both_supported
    tool = ChiebukuroMcp::ProbeTool.new
    result = tool.call(server_context: FakeServerContext.new)
    parsed = JSON.parse(result)
    assert_equal 'supported', parsed['sampling']['status']
    assert_equal 'supported', parsed['elicitation']['status']
  end

  def test_reports_sampling_unsupported
    tool = ChiebukuroMcp::ProbeTool.new
    result = tool.call(server_context: FakeServerContext.new(sampling: :unsupported))
    parsed = JSON.parse(result)
    assert_equal 'unsupported', parsed['sampling']['status']
    assert_match(/does not support sampling/, parsed['sampling']['error'])
    assert_equal 'supported', parsed['elicitation']['status']
  end

  def test_reports_elicitation_unsupported
    tool = ChiebukuroMcp::ProbeTool.new
    result = tool.call(server_context: FakeServerContext.new(elicitation: :unsupported))
    parsed = JSON.parse(result)
    assert_equal 'supported', parsed['sampling']['status']
    assert_equal 'unsupported', parsed['elicitation']['status']
    assert_match(/does not support elicitation/, parsed['elicitation']['error'])
  end

  def test_records_elicitation_decline_as_supported_with_action
    tool = ChiebukuroMcp::ProbeTool.new
    result = tool.call(server_context: FakeServerContext.new(elicitation: :declined))
    parsed = JSON.parse(result)
    assert_equal 'supported', parsed['elicitation']['status']
    assert_equal 'decline', parsed['elicitation']['action']
  end

  def test_raises_when_server_context_is_nil
    tool = ChiebukuroMcp::ProbeTool.new
    assert_raise(ArgumentError) do
      tool.call(server_context: nil)
    end
  end
end
