module ChiebukuroMcp
  # IntentAnalyzer — intent 文字列を解析して
  # (1) 未指定フィールド、(2) キーワードマッチによる default 候補 を返す。
  #
  # 戦略：「全部聞き方式」。required なフィールドは常に missing_fields に入れ、
  # キーワードマッチで得られた値は resolved_hints にだけ積む。
  # ClarificationFormBuilder が resolved_hints を form の default に使う。
  class IntentAnalyzer
    Result = Struct.new(:missing_fields, :resolved_hints)

    def initialize(field_definitions, skip_if_resolved: false)
      @fields = field_definitions
      @skip_if_resolved = skip_if_resolved
    end

    def analyze(intent)
      text = (intent || '').downcase
      missing = @fields.select { |f| f[:required] }.map { |f| f[:name] }
      resolved = {}

      @fields.each do |field|
        kw_map = field[:keywords]
        next unless kw_map

        kw_map.each do |keyword, value|
          if text.include?(keyword.to_s.downcase)
            resolved[field[:name]] = value
            break
          end
        end
      end

      missing = missing.reject { |name| resolved.key?(name) } if @skip_if_resolved

      Result.new(missing, resolved)
    end
  end
end
