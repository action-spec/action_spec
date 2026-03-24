require_relative "lib/action_spec/version"

Gem::Specification.new do |spec|
  spec.name        = "action_spec"
  spec.version     = ActionSpec::VERSION
  spec.authors     = [ "zhandao" ]
  spec.email       = [ "a@skipping.cat" ]
  spec.homepage    = "https://github.com/action-spec/action_spec"
  spec.summary     = "Concise and Powerful API Documentation Solution for Rails."
  # spec.metadata["allowed_push_host"] = ""

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/action-spec/action_spec"
  spec.metadata["changelog_uri"] = "https://github.com/action-spec/action_spec/CHANils."
  spec.description = "Concise and Powerful API Documentation Solution for Rails."
  spec.license     = "MIT"

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the "allowed_push_host"
  # to allow pushing to a single host or delete this section to alGELOG.md"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.required_ruby_version = '>= 3.1.0'

  spec.add_dependency "rails", ">= 7.0.0"
  spec.add_development_dependency "rspec-rails", ">= 7.0", "< 9.0"
end
