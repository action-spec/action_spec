# frozen_string_literal: true

module ActionSpec
  module Doc
    class Dsl
      PARAM_LOCATIONS = %i[header path query cookie].freeze

      def initialize(endpoint)
        @endpoint = endpoint
      end

      PARAM_LOCATIONS.each do |location_name|
        define_method(location_name) do |name, type = String, **options|
          add_param(location_name, name, type, required: false, **options)
        end

        define_method("#{location_name}!") do |name, type = String, **options|
          add_param(location_name, name, type, required: true, **options)
        end

        define_method("in_#{location_name}") do |params|
          add_many(location_name, params, required: false)
        end

        define_method("in_#{location_name}!") do |params|
          add_many(location_name, params, required: true)
        end
      end

      def body(media_type, data: {}, **)
        add_body(media_type, data)
      end

      def body!(media_type, data: {}, **)
        add_body(media_type, data)
      end

      def json(data:, **options)
        body(:json, data:, **options)
      end

      def json!(data:, **options)
        body!(:json, data:, **options)
      end

      def form(data:, **options)
        body(:form, data:, **options)
      end

      def form!(data:, **options)
        body!(:form, data:, **options)
      end

      def data(name, type = String, **options)
        add_body(:form, { name => options.merge(type:) })
      end

      def response(code, description = nil, media_type = nil, desc: nil, **options)
        endpoint.add_response(
          code,
          Response.new(
            code:,
            description: description || desc.to_s,
            media_type:,
            options:
          )
        )
      end

      alias resp response
      alias error response

      private

        attr_reader :endpoint

        def add_param(location_name, name, type, required:, **options)
          schema = ActionSpec::Schema.build(type, **options)
          endpoint.request.add_param(location_name, ActionSpec::Schema::Field.new(name:, required:, schema:))
        end

        def add_many(location_name, params, required:)
          params.each_pair do |name, definition|
            if definition.is_a?(Hash) && !definition.key?(:type) && !definition.key?("type")
              schema_options = definition.symbolize_keys
              if (schema_options.keys - ActionSpec::Schema::OPTION_KEYS).present?
                endpoint.request.add_param(
                  location_name,
                  ActionSpec::Schema::Field.new(name:, required:, schema: ActionSpec::Schema.from_definition(definition))
                )
              else
                add_param(location_name, name, String, required:, **definition)
              end
            elsif definition.is_a?(Hash)
              add_param(location_name, name, definition[:type] || definition["type"] || String, required:, **definition.symbolize_keys.except(:type))
            else
              add_param(location_name, name, definition, required:)
            end
          end
        end

        def add_body(media_type, definition)
          ActionSpec::Schema.build_fields(definition).each_value do |field|
            endpoint.request.add_body(media_type, field)
          end
        end
    end
  end
end
