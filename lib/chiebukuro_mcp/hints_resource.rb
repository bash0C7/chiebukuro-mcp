require_relative 'meta_reader'

module ChiebukuroMcp
  # hints://<db> リソースの中身を Markdown で生成する。
  # カラムの enum 候補・サンプル値・関連テーブルを構造化して提供する。
  class HintsResource
    def initialize(db_path)
      @db_path = db_path
    end

    def call
      meta = MetaReader.read_all(@db_path)
      columns = collect_columns(meta)
      build_markdown(columns, meta[:hints])
    end

    private

    def collect_columns(meta)
      meta[:descriptions].keys
                         .select { |k| k.start_with?('column:') }
                         .map { |k| k.sub('column:', '') }
                         .sort
    end

    def build_markdown(columns, all_hints)
      lines = ['# Column Hints', '']
      if columns.empty?
        lines << '(No column metadata registered.)'
        return lines.join("\n") + "\n"
      end

      columns.each do |col|
        lines << "## #{col}"
        desc = MetaReader.read_all(@db_path)[:descriptions]["column:#{col}"]
        lines << "Description: #{desc}" if desc
        hints = all_hints["column:#{col}"]
        if hints && !hints.empty?
          lines << "Enum values: #{Array(hints[:enum_values]).join(', ')}" if hints[:enum_values]
          lines << "Sample values: #{Array(hints[:sample_values]).join(', ')}" if hints[:sample_values]
          lines << "Related tables: #{Array(hints[:related_tables]).join(', ')}" if hints[:related_tables]
          lines << "Note: #{hints[:note]}" if hints[:note]
        else
          lines << '(No additional hints)'
        end
        lines << ''
      end
      lines.join("\n")
    end
  end
end
