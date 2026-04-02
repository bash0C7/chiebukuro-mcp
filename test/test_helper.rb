# frozen_string_literal: true
require 'test/unit'

class StubEmbedder
  VECTOR_SIZE = 768

  def embed(_text)
    Array.new(VECTOR_SIZE, 0.0)
  end
end
