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

        { "content" => content }.tap do |body|
          body["required"] = true if request.body_required?
        end
      end

      def response(response)
        {
          "description" => response.description.presence || "OK",
          "content" => response_content(response).presence
        }.compact
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

        def response_content(response)
          response.media_types.each_with_object(ActiveSupport::OrderedHash.new) do |(media_type, content), hash|
            normalized = response_media_type_content(content)
            next if normalized.blank?

            hash[MEDIA_TYPE_MAP.fetch(media_type, media_type.to_s)] = normalized
          end
        end

        def response_media_type_content(content)
          {}.tap do |definition|
            if (schema = content[:schema] || infer_schema_from_examples(content)).present?
              definition["schema"] = schema_for(schema)
            end

            if (examples = normalize_response_examples(content[:examples])).present?
              definition["examples"] = examples
            elsif (example = normalize_response_example(content[:example])).present?
              definition["example"] = example
            end
          end.presence
        end

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
          apply_literal_option(definition, "default", schema.default) unless schema.default.respond_to?(:call)
          definition["enum"] = schema.enum if schema.enum.present?
          definition["pattern"] = regex_source(schema.pattern) if schema.pattern.present?
          apply_length(definition, schema.length, definition["type"])
          apply_literal_option(definition, "example", schema.example)
          apply_literal_option(definition, "examples", schema.examples)
          apply_range(definition, schema.range)
          definition
        end

        def apply_literal_option(definition, key, value)
          normalized = openapi_literal(value)
          return if normalized.nil? || normalized.equal?(invalid_openapi_literal)

          definition[key] = normalized
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

        def openapi_literal(value)
          case value
          when nil, String, Integer, Float, TrueClass, FalseClass
            value
          when Array
            normalized = value.map { |item| openapi_literal(item) }
            return invalid_openapi_literal if normalized.any? { |item| item.equal?(invalid_openapi_literal) }

            normalized
          when Hash
            value.each_with_object(ActiveSupport::OrderedHash.new) do |(key, item), normalized|
              item = openapi_literal(item)
              return invalid_openapi_literal if item.equal?(invalid_openapi_literal)

              normalized[key.to_s] = item
            end
          else
            invalid_openapi_literal
          end
        end

        def invalid_openapi_literal
          @invalid_openapi_literal ||= Object.new.freeze
        end

        def normalize_response_example(example)
          normalized = openapi_literal(example)
          return if normalized.nil? || normalized.equal?(invalid_openapi_literal)

          normalized
        end

        def normalize_response_examples(examples)
          return if examples.blank?

          examples.each_with_object(ActiveSupport::OrderedHash.new) do |(name, value), hash|
            normalized = openapi_literal(value)
            next if normalized.nil? || normalized.equal?(invalid_openapi_literal)

            hash[name.to_s] = { "value" => normalized }
          end.presence
        end

        def infer_schema_from_examples(content)
          values =
            if content[:examples].present?
              content[:examples].values
            elsif !content[:example].nil?
              [content[:example]]
            else
              []
            end
          return if values.blank?

          definition = infer_definition(values)
          return if definition.blank?

          ActionSpec::Schema.from_definition(definition)
        end

        def infer_definition(values)
          values = Array(values)
          present_values = values.compact
          return if present_values.empty?

          return infer_object_definition(present_values) if present_values.all? { |value| value.is_a?(Hash) }
          return infer_array_definition(present_values) if present_values.all? { |value| value.is_a?(Array) }

          infer_scalar_definition(present_values)
        end

        def infer_object_definition(values)
          keys = values.flat_map(&:keys).map(&:to_s).uniq
          keys.each_with_object(ActiveSupport::OrderedHash.new) do |key, definition|
            child_values = values.select { |value| value.key?(key) || value.key?(key.to_sym) }.map { |value| value[key] || value[key.to_sym] }
            child_definition = infer_definition(child_values)
            next if child_definition.blank?

            name = values.all? { |value| value.key?(key) || value.key?(key.to_sym) } ? :"#{key}!" : key.to_sym
            definition[name] = child_definition
          end
        end

        def infer_array_definition(values)
          flattened = values.flatten(1)
          item_definition = infer_definition(flattened)
          item_definition ? [item_definition] : []
        end

        def infer_scalar_definition(values)
          return Integer if values.all? { |value| value.is_a?(Integer) }
          return Float if values.all? { |value| value.is_a?(Numeric) }
          return :boolean if values.all? { |value| value == true || value == false }
          return String if values.all? { |value| value.is_a?(String) }

          String
        end
    end
  end
end
