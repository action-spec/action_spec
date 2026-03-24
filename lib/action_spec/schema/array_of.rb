# frozen_string_literal: true

module ActionSpec
  module Schema
    class ArrayOf < Base
      attr_reader :item

      def initialize(item, options = {})
        super(options)
        @item = item
      end

      def cast(value, context:, coerce:, result:, path:)
        unless value.is_a?(Array)
          result.add_error(path.join("."), :invalid)
          return []
        end

        output = value.each_with_index.map do |entry, index|
          item.cast(entry, context:, coerce:, result:, path: [*path, index])
        end
        validate_constraints(output, result:, path:)
        output
      end

      def copy
        self.class.new(item.copy, default:, enum:, range:, pattern:, length:, allow_nil:, allow_blank:, desc: description, example:, examples:)
      end
    end
  end
end
