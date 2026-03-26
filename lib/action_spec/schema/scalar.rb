# frozen_string_literal: true

module ActionSpec
  module Schema
    class Scalar < Base
      attr_reader :type

      def initialize(type, options = {})
        super(options)
        @type = type
      end

      def cast(value, context: nil, coerce:, result:, path:, field: nil)
        candidate = TypeCaster.cast(type, value)
      rescue TypeCaster::CastError => error
        if field
          field.add_error(result, path:, type: :invalid_type, value:, context:, expected: error.expected)
        else
          result.add_error(path.join("."), :invalid_type, expected: error.expected)
        end
        Schema::Missing
      else
        return candidate if candidate.nil?

        validate_constraints(candidate, result:, path:, field:, context:)
        coerce ? candidate : value
      end

      def copy
        self.class.new(type, default:, enum:, range:, pattern:, length:, blank:, desc: description, example:, examples:)
      end

      def blank_value(value)
        TypeCaster.normalize(type) == :string ? value : nil
      end
    end
  end
end
