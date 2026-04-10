# frozen_string_literal: true
require 'test/unit'
require 'sqlite3'
require 'sqlite_vec'
require 'digest'
require 'time'

class StubEmbedder
  VECTOR_SIZE = 768

  def embed(_text)
    Array.new(VECTOR_SIZE, 0.0)
  end
end

# Fake server_context that simulates the subset of MCP::ServerContext used by
# tools that call create_sampling_message / create_elicitation.
# Shared across multiple test files (ProbeTool, QueryWithClarificationTool, ...).
class FakeServerContext
  attr_reader :last_sampling_call, :last_elicitation_call

  def initialize(sampling: :supported, elicitation: :supported, elicitation_content: { ack: true })
    @sampling = sampling
    @elicitation = elicitation
    @elicitation_content = elicitation_content
    @last_sampling_call = nil
    @last_elicitation_call = nil
  end

  def create_sampling_message(**kwargs)
    @last_sampling_call = kwargs
    case @sampling
    when :supported
      { role: 'assistant', content: { type: 'text', text: 'pong' }, model: 'fake' }
    when :unsupported
      raise 'Client does not support sampling.'
    end
  end

  def create_elicitation(**kwargs)
    @last_elicitation_call = kwargs
    case @elicitation
    when :supported
      { action: 'accept', content: @elicitation_content }
    when :declined
      { action: 'decline' }
    when :cancelled
      { action: 'cancel' }
    when :unsupported
      raise 'Client does not support elicitation.'
    end
  end
end

module TestDbHelper
  SCHEMA_SQL = <<~SQL
    CREATE TABLE IF NOT EXISTS memories (
      id           INTEGER PRIMARY KEY AUTOINCREMENT,
      content      TEXT    NOT NULL,
      source       TEXT    NOT NULL,
      content_hash TEXT    NOT NULL UNIQUE,
      embedding    BLOB,
      created_at   TEXT    NOT NULL
    );

    CREATE VIRTUAL TABLE IF NOT EXISTS memories_fts
      USING fts5(content, content='memories', content_rowid='id', tokenize='trigram');

    CREATE VIRTUAL TABLE IF NOT EXISTS memories_vec
      USING vec0(memory_id INTEGER PRIMARY KEY, embedding FLOAT[768]);

    CREATE TRIGGER IF NOT EXISTS memories_ai
      AFTER INSERT ON memories BEGIN
        INSERT INTO memories_fts(rowid, content) VALUES (new.id, new.content);
      END;

    CREATE TRIGGER IF NOT EXISTS memories_ad
      AFTER DELETE ON memories BEGIN
        INSERT INTO memories_fts(memories_fts, rowid, content)
          VALUES ('delete', old.id, old.content);
      END;

    CREATE TABLE IF NOT EXISTS _sqlite_mcp_meta (
      object_type  TEXT NOT NULL,
      object_name  TEXT NOT NULL,
      description  TEXT,
      hints_json   TEXT,
      recipe_sql   TEXT,
      recipe_label TEXT,
      PRIMARY KEY (object_type, object_name)
    );

    INSERT OR REPLACE INTO _sqlite_mcp_meta
      (object_type, object_name, description, hints_json, recipe_sql, recipe_label)
    VALUES
      ('db',     'ruby_knowledge',
       'PicoRuby/CRuby/mruby/ruremaのナレッジ集約DB。trunk変更履歴・ドキュメントを蓄積。FTS5全文検索とvec0ベクトル検索（768次元）の両方が使える',
       NULL, NULL, NULL),
      ('table',  'memories',
       'Ruby関連ナレッジ本体。1コミットにつき記事レコード（source末尾/article）と生diffレコード（source末尾/diff）の2レコードを保存',
       NULL, NULL, NULL),
      ('column', 'memories.content',
       'ナレッジ本文（Markdown形式）。AI生成記事または生git diff',
       NULL, NULL, NULL),
      ('column', 'memories.source',
       'ソース識別子。例: picoruby/picoruby:trunk/article, ruby/ruby:trunk/diff, mruby/mruby:trunk/diff',
       '{"enum_values":["picoruby/picoruby:trunk/article","ruby/ruby:trunk/diff","mruby/mruby:trunk/diff"],"sample_values":["ruby/ruby:trunk/article"],"related_tables":["memories_vec"]}',
       NULL, NULL),
      ('column', 'memories.content_hash',
       'SHA256ハッシュ。同一内容の重複保存を防ぐ（UNIQUEインデックス）',
       NULL, NULL, NULL),
      ('column', 'memories.embedding',
       '768次元float32 blob。memories_vecテーブルのvec0でベクトル類似検索に使用',
       NULL, NULL, NULL),
      ('column', 'memories.created_at',
       '取り込み日時（ISO8601 RFC3339形式）',
       NULL, NULL, NULL),
      ('table',  '_sqlite_mcp_meta',
       'スキーマ自己記述テーブル。chiebukuro_mcp がスキーマ説明を提供するために参照する',
       NULL, NULL, NULL),
      ('recipe', 'recent_articles',
       'trunkの最新記事をcreated_at降順で取得する',
       NULL,
       'SELECT content, source, created_at FROM memories WHERE source LIKE :source_like AND created_at BETWEEN :from_date AND :to_date ORDER BY created_at DESC LIMIT :limit',
       '最新記事'),
      ('clarification_field', 'source_like',
       'どの派生Rubyのtrunk変更記事を見るか',
       '{"type":"string","required":true,"order":1,"keywords":{"CRuby":"ruby/ruby:trunk/%","PicoRuby":"picoruby/picoruby:trunk/%","mruby":"mruby/mruby:trunk/%"},"enum_values":["ruby/ruby:trunk/%","picoruby/picoruby:trunk/%","mruby/mruby:trunk/%"]}',
       NULL, NULL),
      ('clarification_field', 'from_date',
       '期間の開始日 (YYYY-MM-DD)',
       '{"type":"date","required":true,"order":2}',
       NULL, NULL),
      ('clarification_field', 'to_date',
       '期間の終了日 (YYYY-MM-DD)',
       '{"type":"date","required":true,"order":3}',
       NULL, NULL),
      ('clarification_field', 'limit',
       '最大件数 (1-100 程度)',
       '{"type":"integer","required":true,"order":4}',
       NULL, NULL);
  SQL

  def self.setup_db(db_path)
    db = SQLite3::Database.new(db_path)
    db.enable_load_extension(true)
    SqliteVec.load(db)
    db.enable_load_extension(false)
    db.execute_batch(SCHEMA_SQL)
  ensure
    db&.close
  end

  def self.insert_memory(db_path, content, source, embedder)
    db = SQLite3::Database.new(db_path)
    db.enable_load_extension(true)
    SqliteVec.load(db)
    db.enable_load_extension(false)
    db.execute('PRAGMA journal_mode=WAL')

    content_hash = Digest::SHA256.hexdigest(content)
    return nil if db.execute('SELECT id FROM memories WHERE content_hash = ?', [content_hash]).first

    created_at = Time.now.iso8601
    db.execute(
      'INSERT INTO memories (content, source, content_hash, created_at) VALUES (?, ?, ?, ?)',
      [content, source, content_hash, created_at]
    )
    id = db.last_insert_row_id
    embedding_blob = embedder.embed(content).pack('f*')
    db.execute('INSERT INTO memories_vec(memory_id, embedding) VALUES (?, ?)', [id, embedding_blob])
    id
  ensure
    db&.close
  end
end
