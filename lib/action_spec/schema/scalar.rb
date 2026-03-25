# frozen_string_literal: true

module ActionSpec
  module Schema
    class Scalar < Base
      attr_reader :type

      def initialize(type, options = {})
        super(options)
        @type = type
      end

      def cast(value, context: nil, coerce:, result:, path:)
        candidate = TypeCaster.cast(type, value)
      rescue TypeCaster::CastError => error
        result.add_error(path.join("."), :invalid_type, expected: error.expected)
        Schema::Missing
      else
        return candidate if candidate.nil?

        validate_constraints(candidate, result:, path:)
        coerce ? candidate : value
      end

      def copy
        self.class.new(type, default:, enum:, range:, pattern:, length:, blank:, desc: description, example:, examples:)
      end
    end
  end
end
