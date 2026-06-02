# frozen_string_literal: true

module ActionSpec
  module Schema
    class ObjectOf < Base
      attr_reader :fields

      def initialize(fields, options = {})
        super(options)
        @fields = fields
      end

      def cast(value, context:, coerce:, result:, path:, field: nil)
        source = normalize_source(value, result:, path:, field:, context:, invalid_value: value)
        return Schema::Missing if source.equal?(Schema::Missing)

        output = ActiveSupport::HashWithIndifferentAccess.new
        fields.each_value do |field|
          resolved = Resolver.new(
            field:,
            source:,
            context:,
            coerce:,
            result:,
            path:
          ).resolve
          output[field.output_name] = resolved unless resolved.equal?(Schema::Missing)
        end
        output.presence || (source.present? ? output : Schema::Missing)
      end

      def materialize_missing(context:, coerce:, result:, path:)
        cast({}, context:, coerce:, result:, path:, field: nil)
      end

      def copy
        self.class.new(fields.transform_values(&:copy), default:, enum:, range:, pattern:, length:, blank:, desc: description, example:, examples:)
      end

      def custom_validation?
        custom_validation_fields.any?
      end

      def custom_validation_fields
        @custom_validation_fields ||= fields.each_value.select(&:custom_validation?).freeze
      end

      private

        def normalize_source(value, result:, path:, field:, context:, invalid_value:)
          return {} if value.nil?
          return value.to_unsafe_h.with_indifferent_access if value.is_a?(ActionController::Parameters)
          return value.with_indifferent_access if value.is_a?(Hash)

          if field
            field.add_error(result, path:, type: :invalid, value: invalid_value, context:)
          else
            result.add_error(path.join("."), :invalid)
          end
          Schema::Missing
        end
    end
  end
end
