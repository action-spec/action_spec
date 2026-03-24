require "action_spec/version"
require "active_support"
require "active_support/core_ext"
require "active_model"
require "action_spec/configuration"
require "action_spec/header_hash"
require "action_spec/validation_result"
require "action_spec/invalid_parameters"
require "action_spec/doc"
require "action_spec/schema"
require "action_spec/validator"
require "action_spec/railtie"

module ActionSpec
  class << self
    def config
      @config ||= Configuration.new
    end

    def configure
      yield config
    end
  end
end
