# frozen_string_literal: true

module ActionSpec
  module Schema
    class ArrayOf < Base
      attr_reader :item

      def initialize(item, options = {})
        super(options)
        @item = item
      end

      def cast(value, context:, coerce:, result:, path:, field: nil)
        unless value.is_a?(Array)
          if field
            field.add_error(result, path:, type: :invalid, value:, context:)
          else
            result.add_error(path.join("."), :invalid)
          end
          return []
        end

        output = value.each_with_index.map do |entry, index|
          item.cast(entry, context:, coerce:, result:, path: [*path, index], field: nil)
        end
        validate_constraints(output, result:, path:, field:, context:)
        output
      end

      def copy
        self.class.new(item.copy, default:, enum:, range:, pattern:, length:, blank:, desc: description, example:, examples:)
      end

      def custom_validation?
        item.custom_validation?
      end
    end
  end
end
