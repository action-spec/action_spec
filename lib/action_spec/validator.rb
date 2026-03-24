# frozen_string_literal: true

require "action_spec/validator/runner"

module ActionSpec
  module Validator
    extend ActiveSupport::Concern

    def px
      @px ||= ValidationResult.empty_px
    end

    def validate_params!
      @px = validate_with(coerce: false)
    end

    def validate_and_coerce_params!
      @px = validate_with(coerce: true)
    end

    private

      def validate_with(coerce:)
        endpoint = self.class.respond_to?(:action_spec_for) ? self.class.action_spec_for(action_name) : nil
        return ValidationResult.empty_px unless endpoint

        result = Runner.new(endpoint:, controller: self, coerce:).call
        raise ActionSpec.config.invalid_parameters_exception_class.new(result) if result.invalid?

        result.px
      end
  end
end
