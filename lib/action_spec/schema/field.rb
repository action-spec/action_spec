# frozen_string_literal: true

module ActionSpec
  module Schema
    class Field
      attr_reader :name, :schema, :transform, :px_key, :scopes

      def initialize(name:, required:, schema:, transform: nil, px_key: nil, scopes: [])
        @name = name.to_sym
        @required = required
        @schema = schema
        @transform = transform
        @px_key = px_key&.to_sym
        @scopes = Array(scopes).map(&:to_sym).freeze
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

      def copy
        self.class.new(name:, required: required?, schema: schema.copy, transform:, px_key:, scopes:)
      end

      private

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

        def invoke_context_transform(context, symbol, value)
          method = context.method(symbol)
          return context.public_send(symbol) if method.arity.zero?

          context.public_send(symbol, value)
        end
    end
  end
end
