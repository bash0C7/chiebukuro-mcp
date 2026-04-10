module ChiebukuroMcp
  # ClarificationFormBuilder — missing_fields / resolved_hints / meta_hints から
  # elicitation/create に渡す JSON Schema を組み立てる。
  #
  # 制約（MCP elicitation form mode 仕様）:
  # - flat object のみ
  # - プリミティブ型（string / number / integer / boolean）+ enum (oneOf) のみ
  # - nested object / array-of-object は使えない
  class ClarificationFormBuilder
    def initialize(field_definitions)
      @fields = field_definitions.each_with_object({}) { |f, h| h[f[:name]] = f }
    end

    def build(missing_fields, resolved_hints, meta_hints)
      properties = {}
      missing_fields.each do |name|
        field = @fields[name]
        next unless field

        prop = build_property(field, meta_hints)
        default = resolved_hints[name]
        prop[:default] = default if default
        properties[name] = prop
      end

      {
        type: 'object',
        properties: properties,
        required: missing_fields.dup
      }
    end

    private

    def build_property(field, meta_hints)
      base = { description: field[:description] || field[:name].to_s }

      case field[:type]
      when :date
        base.merge(type: 'string', format: 'date')
      when :integer
        base.merge(type: 'integer')
      when :number
        base.merge(type: 'number')
      when :boolean
        base.merge(type: 'boolean')
      when :string
        string_property(base, field, meta_hints)
      else
        base.merge(type: 'string')
      end
    end

    def string_property(base, field, meta_hints)
      hint_key = field[:meta_hint_key]
      if hint_key
        hints = meta_hints["column:#{hint_key}"]
        if hints && hints[:enum_values] && !hints[:enum_values].empty?
          one_of = hints[:enum_values].map { |v| { const: v, title: v } }
          return base.merge(type: 'string', oneOf: one_of)
        end
      end
      base.merge(type: 'string')
    end
  end
end
