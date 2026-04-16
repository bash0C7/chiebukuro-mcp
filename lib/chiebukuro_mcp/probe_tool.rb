require 'json'

module ChiebukuroMcp
  # ProbeTool は MCP ホスト（クライアント）が sampling と elicitation の
  # capability を宣言しているかを実地で確認するための実証ツール。
  #
  # ホスト側 LLM に最小の sampling 要求と elicitation 要求を送り、
  # 成功 / 失敗 / 応答内容を JSON でまとめて返す。
  # capability が無いホストでは create_* が例外を投げるため、
  # それを捕まえて status: "unsupported" として記録する。
  class ProbeTool
    def call(server_context:)
      raise ArgumentError, 'server_context is required' unless server_context

      results = {
        sampling: probe_sampling(server_context),
        elicitation: probe_elicitation(server_context),
      }
      JSON.generate(results)
    end

    private

    def probe_sampling(ctx)
      response = ctx.create_sampling_message(
        messages: [{ role: 'user', content: { type: 'text', text: "Reply with the single word 'pong'." } }],
        max_tokens: 10,
        system_prompt: 'You are a probe responder. Reply tersely.'
      )
      {
        status: 'supported',
        model: response[:model] || response['model'],
        text: extract_text(response),
      }
    rescue => e
      { status: 'unsupported', error: e.message }
    end

    def probe_elicitation(ctx)
      response = ctx.create_form_elicitation(
        message: 'chiebukuro-mcp probe: please decline to confirm elicitation works.',
        requested_schema: {
          type: 'object',
          properties: {
            ack: { type: 'boolean', description: 'Acknowledge that elicitation works' }
          },
          required: ['ack']
        }
      )
      {
        status: 'supported',
        action: response[:action] || response['action'],
        content: response[:content] || response['content'],
      }
    rescue => e
      { status: 'unsupported', error: e.message }
    end

    def extract_text(response)
      content = response[:content] || response['content']
      return nil unless content.is_a?(Hash)

      content[:text] || content['text']
    end
  end
end
