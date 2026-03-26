# frozen_string_literal: true

module ActionSpec
  module Schema
    class Field
      attr_reader :name, :schema, :transform, :validate, :px_key, :scopes, :error_message

      def initialize(name:, required:, schema:, transform: nil, validate: nil, px_key: nil, scopes: [], error_message: nil)
        @name = name.to_sym
        @required = required
        @schema = schema
        @transform = transform
        @validate = validate
        @px_key = px_key&.to_sym
        @scopes = Array(scopes).map(&:to_sym).freeze
        @error_message = error_message
      end

      def required?
        @required
      end

      def default_value
        schema.default
      end

      def output_name
        px_key || name
      end

      def transform_value(value, context: nil)
        return value if transform.nil? || value.equal?(ActionSpec::Schema::Missing)

        case transform
        when Symbol, String then apply_symbol_transform(value, context:)
        when Proc then apply_proc_transform(value, context:)
        else value
        end
      end

      def validate_value(value, context: nil)
        return true if validate.nil? || value.equal?(ActionSpec::Schema::Missing)

        case validate
        when Proc then apply_validation_proc(value, context:)
        else true
        end
      end

      def custom_validation?
        validate.present? || schema.custom_validation?
      end

      def add_error(result, path:, type:, value:, context: nil, **options)
        result.add_error(path.join("."), type, message: resolve_error_message(type, value, context:), **options)
      end

      def copy
        self.class.new(name:, required: required?, schema: schema.copy, transform:, validate:, px_key:, scopes:, error_message:)
      end

      private

        def resolve_error_message(type, value, context:)
          case error_message
          when nil then nil
          when String then error_message
          when Proc then apply_error_proc(type, value, context:)
          else error_message.to_s
          end
        end

        def apply_symbol_transform(value, context:)
          symbol = transform.to_sym
          return value.public_send(symbol) if value.respond_to?(symbol)
          return invoke_context_transform(context, symbol, value) if context&.respond_to?(symbol, true)

          value
        end

        def apply_proc_transform(value, context:)
          return context.instance_exec(&transform) if context && transform.arity.zero?
          return context.instance_exec(value, &transform) if context && (transform.arity == 1 || transform.arity.negative?)
          return transform.call if transform.arity.zero?

          transform.call(value)
        end

        def apply_validation_proc(value, context:)
          return context.instance_exec(&validate) if context && validate.arity.zero?
          return context.instance_exec(value, &validate) if context && (validate.arity == 1 || validate.arity.negative?)
          return validate.call if validate.arity.zero?

          validate.call(value)
        end

        def apply_error_proc(type, value, context:)
          return context.instance_exec(&error_message) if context && error_message.arity.zero?
          return context.instance_exec(type, &error_message) if context && error_message.arity == 1
          return context.instance_exec(type, value, &error_message) if context && (error_message.arity == 2 || error_message.arity.negative?)
          return error_message.call if error_message.arity.zero?
          return error_message.call(type) if error_message.arity == 1

          error_message.call(type, value)
        end

        def invoke_context_transform(context, symbol, value)
          method = context.method(symbol)
          return context.public_send(symbol) if method.arity.zero?

          context.public_send(symbol, value)
        end
    end
  end
end
