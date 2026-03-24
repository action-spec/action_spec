# frozen_string_literal: true

module ActionSpec
  module OpenApi
    class Schema
      LOCATION_MAP = {
        header: "header",
        path: "path",
        query: "query",
        cookie: "cookie"
      }.freeze

      MEDIA_TYPE_MAP = {
        json: "application/json",
        form: "multipart/form-data"
      }.freeze

      def parameter(field, location:)
        {
          "name" => parameter_name(field, location),
          "in" => LOCATION_MAP.fetch(location),
          "required" => location == :path ? true : field.required?,
          "schema" => schema_for(field.schema)
        }.tap do |parameter|
          if (description = field.schema.description).present?
            parameter["description"] = description
          end
        end
      end

      def request_body(request)
        content = request.body_media_types.each_with_object(ActiveSupport::OrderedHash.new) do |(media_type, fields), hash|
          hash[MEDIA_TYPE_MAP.fetch(media_type, media_type.to_s)] = {
            "schema" => object_schema(fields.fields)
          }
        end
        return if content.empty?

        { "content" => content }
      end

      def schema_for(schema)
        case schema
        when ActionSpec::Schema::Scalar then scalar_schema(schema)
        when ActionSpec::Schema::ObjectOf then object_schema(schema.fields.values, schema:)
        when ActionSpec::Schema::ArrayOf then array_schema(schema)
        else { "type" => "string" }
        end
      end

      private

        def parameter_name(field, location)
          return field.name.to_s if location != :header

          field.name.to_s.split("_").map(&:capitalize).join("-")
        end

        def scalar_schema(schema)
          type = scalar_type(schema.type)
          definition =
            case type
            when "string"
              { "type" => "string" }
            when "integer"
              { "type" => "integer" }
            when "number"
              { "type" => "number", "format" => number_format(schema.type) }.compact
            when "boolean"
              { "type" => "boolean" }
            when "file"
              { "type" => "string", "format" => "binary" }
            when "object"
              { "type" => "object" }
            else
              { "type" => "string" }
            end

          definition["format"] = string_format(schema.type) if string_format(schema.type)
          apply_common_options(definition, schema)
        end

        def object_schema(fields, schema: nil)
          definition = {
            "type" => "object",
            "properties" => fields.each_with_object(ActiveSupport::OrderedHash.new) do |field, properties|
              properties[field.name.to_s] = schema_for(field.schema)
            end
          }

          required = fields.select(&:required?).map { |field| field.name.to_s }
          definition["required"] = required if required.any?

          schema ? apply_common_options(definition, schema) : definition
        end

        def array_schema(schema)
          definition = {
            "type" => "array",
            "items" => schema_for(schema.item)
          }

          apply_common_options(definition, schema)
        end

        def apply_common_options(definition, schema)
          definition["description"] = schema.description if schema.description.present?
          definition["default"] = schema.default unless schema.default.respond_to?(:call) || schema.default.nil?
          definition["enum"] = schema.enum if schema.enum.present?
          definition["pattern"] = regex_source(schema.pattern) if schema.pattern.present?
          apply_length(definition, schema.length, definition["type"])
          definition["example"] = schema.example if schema.example.present?
          definition["examples"] = schema.examples if schema.examples.present?
          apply_range(definition, schema.range)
          definition
        end

        def apply_range(definition, range)
          return if range.blank?

          rules = range.symbolize_keys
          definition["minimum"] = rules[:ge] if rules.key?(:ge)
          definition["exclusiveMinimum"] = rules[:gt] if rules.key?(:gt)
          definition["maximum"] = rules[:le] if rules.key?(:le)
          definition["exclusiveMaximum"] = rules[:lt] if rules.key?(:lt)
        end

        def apply_length(definition, length, type)
          return if length.blank?

          rules = length.symbolize_keys
          return unless type == "string"

          definition["minLength"] = rules[:minimum] if rules.key?(:minimum)
          definition["maxLength"] = rules[:maximum] if rules.key?(:maximum)
        end

        def scalar_type(type)
          case ActionSpec::Schema::TypeCaster.normalize(type)
          when :string then "string"
          when :integer then "integer"
          when :float, :decimal then "number"
          when :boolean then "boolean"
          when :date, :datetime, :time then "string"
          when :file then "file"
          when :object then "object"
          else "string"
          end
        end

        def string_format(type)
          case ActionSpec::Schema::TypeCaster.normalize(type)
          when :date then "date"
          when :datetime then "date-time"
          when :time then "time"
          end
        end

        def number_format(type)
          case ActionSpec::Schema::TypeCaster.normalize(type)
          when :float then "float"
          when :decimal then "double"
          end
        end

        def regex_source(pattern)
          pattern.is_a?(Regexp) ? pattern.source : pattern.to_s
        end
    end
  end
end
