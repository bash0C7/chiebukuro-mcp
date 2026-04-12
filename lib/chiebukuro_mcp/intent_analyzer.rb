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

    def analyze(intent, prefilled = {})
      text = (intent || '').downcase
      missing = @fields.select { |f| f[:required] }.map { |f| f[:name] }
      resolved = {}
      prefilled.each { |k, v| resolved[k.to_sym] = v unless v.nil? }

      @fields.each do |field|
        next if resolved.key?(field[:name])

        kw_map = field[:keywords]
        next unless kw_map

        kw_map.each do |keyword, value|
          if text.include?(keyword.to_s.downcase)
            resolved[field[:name]] = value
            break
          end
        end
      end

      # Field-level default:
      # 優先順位は prefilled > keyword match > default。ここまでで resolved に
      # 載らなかった field に :default があれば最後に fallback として積む。
      @fields.each do |field|
        next if resolved.key?(field[:name])
        next if field[:default].nil?

        resolved[field[:name]] = field[:default]
      end

      missing = missing.reject { |name| resolved.key?(name) } if @skip_if_resolved

      Result.new(missing, resolved)
    end
  end
end
