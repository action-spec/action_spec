# frozen_string_literal: true

module ActionSpec
  module Schema
    class Resolver
      def initialize(field:, source:, context:, coerce:, result:, path:)
        @field = field
        @source = source
        @context = context
        @coerce = coerce
        @result = result
        @path = [*path, field.name]
      end

        def resolve
          return resolve_missing unless present?

          return resolve_nil if value.nil?
          return finalize(schema.blank_value(value)) if blank_string_allowed?
          return resolve_blank if blank_disallowed?

        finalize(schema.cast(value, context:, coerce:, result:, path:, field:))
      end

      private

        attr_reader :field, :source, :context, :coerce, :result, :path

        def schema
          field.schema
        end

        def value
          source[field.name]
        end

        def present?
          source.key?(field.name)
        end

        def resolve_missing
          if schema.default.respond_to?(:call)
            return finalize(schema.cast(evaluate_default(schema.default), context:, coerce:, result:, path:, field:))
          end
          return finalize(schema.cast(schema.default, context:, coerce:, result:, path:, field:)) unless schema.default.nil?
          return finalize(schema.materialize_missing(context:, coerce:, result:, path:)) unless field.required?

          field.add_error(result, path:, type: :required, value: nil, context:)
          Schema::Missing
        end

        def resolve_nil
          field.add_error(result, path:, type: field.required? ? :required : :blank, value:, context:)
          Schema::Missing
        end

        def resolve_blank
          field.add_error(result, path:, type: :blank, value:, context:)
          Schema::Missing
        end

        def blank_disallowed?
          !schema.blank_allowed? && value.respond_to?(:blank?) && value.blank?
        end

        def blank_string_allowed?
          # Keep blank-string semantics explicit: preserve only values that the schema
          # can meaningfully carry as blank, and normalize the rest to nil.
          schema.blank_allowed? && value.is_a?(String) && value.blank?
        end

        def finalize(resolved)
          return resolved if resolved.equal?(Schema::Missing)

          field.transform_value(resolved, context:)
        end

        def evaluate_default(default_proc)
          return context.instance_exec(&default_proc) if context && default_proc.arity.zero?
          return default_proc.call(context) if context && default_proc.arity == 1

          default_proc.call
        end
    end
  end
end
