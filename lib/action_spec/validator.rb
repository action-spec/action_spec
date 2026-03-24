# frozen_string_literal: true

require "action_spec/validator/runner"

module ActionSpec
  module Validator
    extend ActiveSupport::Concern

    included do
      rescue_from ActionSpec::InvalidParameters, with: :render_invalid_parameters if ActionSpec.config.rescue_invalid_parameters
    end

    def px
      @px ||= ActiveSupport::HashWithIndifferentAccess.new
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
        return ActiveSupport::HashWithIndifferentAccess.new unless endpoint

        result = Runner.new(endpoint:, controller: self, coerce:).call
        raise ActionSpec.config.invalid_parameters_exception_class.new(result) if result.invalid?

        result.px
      end

      def render_invalid_parameters(error)
        if (renderer = ActionSpec.config.invalid_parameters_renderer)
          return renderer.arity == 2 ? renderer.call(self, error) : instance_exec(error, &renderer)
        end

        render json: { errors: error.errors.to_hash(full_messages: true) },
               status: ActionSpec.config.invalid_parameters_status
      end
  end
end
