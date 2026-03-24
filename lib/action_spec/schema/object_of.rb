# frozen_string_literal: true

module ActionSpec
  module Schema
    class ObjectOf < Base
      attr_reader :fields

      def initialize(fields, options = {})
        super(options)
        @fields = fields
      end

      def cast(value, context:, coerce:, result:, path:)
        source = normalize_source(value, result:, path:)
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
          output[field.name] = resolved unless resolved.equal?(Schema::Missing)
        end
        output.presence || (source.present? ? output : Schema::Missing)
      end

      def materialize_missing(context:, coerce:, result:, path:)
        cast({}, context:, coerce:, result:, path:)
      end

      def copy
        self.class.new(fields.transform_values(&:copy), default:, enum:, range:, pattern:, allow_nil:, allow_blank:)
      end

      private

        def normalize_source(value, result:, path:)
          return {} if value.nil?
          return value.to_unsafe_h.with_indifferent_access if value.is_a?(ActionController::Parameters)
          return value.with_indifferent_access if value.is_a?(Hash)

          result.add_error(path.join("."), :invalid)
          Schema::Missing
        end
    end
  end
end
