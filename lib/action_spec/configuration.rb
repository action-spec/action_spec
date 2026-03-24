# frozen_string_literal: true

module ActionSpec
  class Configuration
    attr_accessor :invalid_parameters_exception_class, :open_api_output, :open_api_title, :open_api_version,
                  :open_api_server_url
    attr_reader :error_messages

    def initialize
      @invalid_parameters_exception_class = ActionSpec::InvalidParameters
      @open_api_output = "docs/openapi.yml"
      @open_api_title = nil
      @open_api_version = nil
      @open_api_server_url = nil
      @error_messages = ActiveSupport::HashWithIndifferentAccess.new
    end

    def error_messages=(value)
      @error_messages = ActiveSupport::HashWithIndifferentAccess.new(value)
    end

    def message_for(attribute, type, options = {})
      configured = error_messages.dig(attribute.to_sym, type.to_sym) || error_messages[type.to_sym]
      return if configured.blank?

      configured.respond_to?(:call) ? configured.call(attribute.to_sym, options) : configured
    end

    def dup
      self.class.new.tap do |copy|
        copy.invalid_parameters_exception_class = invalid_parameters_exception_class
        copy.open_api_output = open_api_output
        copy.open_api_title = open_api_title
        copy.open_api_version = open_api_version
        copy.open_api_server_url = open_api_server_url
        copy.error_messages = error_messages.deep_dup
      end
    end
  end
end
