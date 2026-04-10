module ChiebukuroMcp
  # SqlTemplateEngine — recipes と clarification 回答から
  # 最終 SQL (positional placeholders) + params 配列を生成する。
  #
  # 安全策:
  # - テンプレートは SELECT / WITH で始まるものだけ許可
  # - named placeholder (`:key`) を `?` に変換し、params を順序保証で構築
  # - slot が回答に無い場合は ArgumentError
  # - :limit / :offset のような数値系キーは Integer にキャスト
  class SqlTemplateEngine
    INTEGER_SLOT_NAMES = %i[limit offset].freeze
    PLACEHOLDER_REGEX = /:([a-zA-Z_][a-zA-Z0-9_]*)/.freeze

    def initialize(recipes)
      @recipes = recipes
    end

    def build(intent, content)
      raise ArgumentError, 'no recipes available' if @recipes.empty?

      recipe = pick_recipe(intent)
      validate_select!(recipe[:sql])
      substitute(recipe[:sql], content)
    end

    private

    def pick_recipe(intent)
      text = (intent || '').downcase
      best = nil
      best_score = 0

      @recipes.each do |r|
        keywords = Array(r[:intent_keywords])
        next if keywords.empty?

        score = keywords.count { |k| text.include?(k.to_s.downcase) }
        if score > best_score
          best = r
          best_score = score
        end
      end

      best || default_recipe || @recipes.last
    end

    def default_recipe
      @recipes.find { |r| Array(r[:intent_keywords]).empty? }
    end

    def validate_select!(sql)
      normalized = sql.strip.upcase
      unless normalized.start_with?('SELECT') || normalized.start_with?('WITH')
        raise ArgumentError, 'Only SELECT/WITH templates are allowed'
      end
    end

    def substitute(template, content)
      params = []
      sql = template.gsub(PLACEHOLDER_REGEX) do
        key = Regexp.last_match(1).to_sym
        value = lookup_value(content, key)
        params << coerce(key, value)
        '?'
      end
      [sql, params]
    end

    def lookup_value(content, key)
      if content.key?(key)
        content[key]
      elsif content.key?(key.to_s)
        content[key.to_s]
      else
        raise ArgumentError, "missing slot: #{key}"
      end
    end

    def coerce(key, value)
      if INTEGER_SLOT_NAMES.include?(key)
        Integer(value)
      else
        value
      end
    end
  end
end
