# frozen_string_literal: true

module ActionSpec
  module Schema
    class Base
      attr_reader :default, :enum, :range, :pattern, :length, :blank, :description, :example, :examples

      def initialize(options = {})
        options = options.symbolize_keys
        @default = options[:default]
        @enum = options[:enum]
        @range = options[:range]
        @pattern = options[:pattern]
        @length = options[:length]
        @blank = options.key?(:blank) ? options[:blank] : options.fetch(:allow_blank, true)
        @description = options[:desc] || options[:description]
        @example = options[:example]
        @examples = options[:examples]
      end

      alias allow_blank blank

      def materialize_missing(context:, coerce:, result:, path:)
        Schema::Missing
      end

      def blank_allowed?
        blank != false
      end

      def validate_constraints(value, result:, path:)
        return if value.nil?

        validate_enum(value, result:, path:)
        validate_range(value, result:, path:)
        validate_pattern(value, result:, path:)
      end

      def copy
        raise NotImplementedError
      end

      def custom_validation?
        false
      end

      private

        def add_error(result, path, type, **options)
          result.add_error(path.join("."), type, **options)
        end

        def validate_enum(value, result:, path:)
          return if enum.blank?
          return if Array(enum).include?(value)

          add_error(result, path, :inclusion)
        end

        def validate_range(value, result:, path:)
          return if range.blank?

          rules = range.symbolize_keys
          add_error(result, path, :greater_than_or_equal_to, count: rules[:ge]) if rules.key?(:ge) && value < rules[:ge]
          add_error(result, path, :greater_than, count: rules[:gt]) if rules.key?(:gt) && value <= rules[:gt]
          add_error(result, path, :less_than_or_equal_to, count: rules[:le]) if rules.key?(:le) && value > rules[:le]
          add_error(result, path, :less_than, count: rules[:lt]) if rules.key?(:lt) && value >= rules[:lt]
        end

        def validate_pattern(value, result:, path:)
          return if pattern.blank?

          matcher = pattern.is_a?(Regexp) ? pattern : Regexp.new(pattern.to_s)
          return if value.to_s.match?(matcher)

          add_error(result, path, :invalid)
        end
    end
  end
end
