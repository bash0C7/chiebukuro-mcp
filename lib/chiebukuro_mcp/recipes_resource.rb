require_relative 'meta_reader'

module ChiebukuroMcp
  # recipes://<db> リソースの中身を Markdown で生成する。
  # _sqlite_mcp_meta の object_type='recipe' 行から SQL 本文とラベルを読み取る。
  class RecipesResource
    def initialize(db_path)
      @db_path = db_path
    end

    def call
      recipes = MetaReader.read_all(@db_path)[:recipes]
      if recipes.empty?
        "# Query Recipes\n\n(No recipes registered.)\n"
      else
        build_markdown(recipes)
      end
    end

    private

    def build_markdown(recipes)
      lines = ['# Query Recipes', '']
      recipes.each do |r|
        heading = r[:label] && !r[:label].empty? ? r[:label] : r[:name]
        lines << "## #{heading}"
        lines << r[:description] if r[:description] && !r[:description].empty?
        lines << ''
        lines << '```sql'
        lines << r[:sql]
        lines << '```'
        lines << ''
      end
      lines.join("\n")
    end
  end
end
