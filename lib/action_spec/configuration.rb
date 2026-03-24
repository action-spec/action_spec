# frozen_string_literal: true

module ActionSpec
  class Configuration
    attr_accessor :invalid_parameters_exception_class, :invalid_parameters_status, :rescue_invalid_parameters,
                  :invalid_parameters_renderer
    attr_reader :error_messages

    def initialize
      @invalid_parameters_exception_class = ActionSpec::InvalidParameters
      @invalid_parameters_status = :bad_request
      @rescue_invalid_parameters = true
      @invalid_parameters_renderer = nil
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
        copy.invalid_parameters_status = invalid_parameters_status
        copy.rescue_invalid_parameters = rescue_invalid_parameters
        copy.invalid_parameters_renderer = invalid_parameters_renderer
        copy.error_messages = error_messages.deep_dup
      end
    end
  end
end
