Gem::Specification.new do |spec|
  spec.name          = 'chiebukuro_mcp'
  spec.version       = '0.1.0'
  spec.authors       = ['bash0C7']
  spec.summary       = 'Read-only SQLite MCP server with schema-aware query support'
  spec.files         = Dir['lib/**/*.rb'] + Dir['exe/*']
  spec.bindir        = 'exe'
  spec.executables   = ['chiebukuro-mcp']
  spec.require_paths = ['lib']
end
