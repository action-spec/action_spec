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
        return resolve_blank if blank_disallowed?

        finalize(schema.cast(value, context:, coerce:, result:, path:))
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
            return finalize(schema.cast(evaluate_default(schema.default), context:, coerce:, result:, path:))
          end
          return finalize(schema.cast(schema.default, context:, coerce:, result:, path:)) unless schema.default.nil?
          return finalize(schema.materialize_missing(context:, coerce:, result:, path:)) unless field.required?

          result.add_error(path.join("."), :required)
          Schema::Missing
        end

        def resolve_nil
          result.add_error(path.join("."), field.required? ? :required : :blank)
          Schema::Missing
        end

        def resolve_blank
          result.add_error(path.join("."), :blank)
          Schema::Missing
        end

        def blank_disallowed?
          !schema.blank_allowed? && value.respond_to?(:blank?) && value.blank?
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
