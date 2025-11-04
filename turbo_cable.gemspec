require_relative "lib/turbo_cable/version"

Gem::Specification.new do |spec|
  spec.name        = "turbo_cable"
  spec.version     = TurboCable::VERSION
  spec.authors     = [ "Sam Ruby" ]
  spec.email       = [ "rubys@intertwingly.net" ]
  spec.homepage    = "https://github.com/rubys/turbo_cable"
  spec.summary     = "Lightweight WebSocket-based Turbo Streams for single-server Rails deployments"
  spec.description = "TurboCable replaces Action Cable with a custom WebSocket implementation for Turbo Streams, providing 79-85% memory savings (134-144MB per process) while maintaining full API compatibility. Designed for single-server deployments with zero external dependencies beyond Ruby's standard library."
  spec.license     = "MIT"

  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/rubys/turbo_cable"
  spec.metadata["changelog_uri"] = "https://github.com/rubys/turbo_cable/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md", "CHANGELOG.md", "EXAMPLES.md"]
  end

  spec.add_dependency "rails", ">= 7.0"
end
