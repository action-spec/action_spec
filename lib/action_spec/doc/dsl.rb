# frozen_string_literal: true

module ActionSpec
  module Doc
    class Dsl
      PARAM_LOCATIONS = %i[header path query cookie].freeze

      def initialize(endpoint)
        @endpoint = endpoint
        @scopes = []
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

      def body(media_type, data: {}, required: false, **)
        add_body(media_type, data, required:)
      end

      def body!(media_type, data: {}, **)
        add_body(media_type, data, required: true)
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

      def scope(name, &block)
        scopes.push(name.to_sym)
        instance_exec(&block)
      ensure
        scopes.pop
      end

      def openapi(enabled)
        endpoint.options[:openapi] = enabled
      end

      RESPONSE_MEDIA_TYPES = %i[json form].freeze

      def response(code, description = nil, media_type = nil, desc: nil, data: nil, example: nil, examples: nil, **options)
        description, media_type = normalize_response_arguments(description, media_type)
        schema, example, examples = normalize_response_body(description, data:, example:, examples:, options:)
        endpoint.add_response(
          code,
          Response.new(
            code:,
            description: resolved_description(description, desc),
            media_type: media_type || ActionSpec.config.default_response_media_type,
            schema:,
            example:,
            examples:,
            options:
          )
        )
      end

      def error(code, description = nil, media_type = nil, desc: nil, **options)
        response(code, description, media_type, desc: desc || "Error", **options)
      end

      def errors(code, examples = nil, media_type = nil, desc: "Error", **options)
        response(code, nil, media_type, desc:, examples: examples || options, **options.except(*Array((examples || options).keys)))
      end

      private

        attr_reader :endpoint
        attr_reader :scopes

        def normalize_response_arguments(description, media_type)
          return [nil, description] if media_type.nil? && response_media_type?(description)

          [description, media_type]
        end

        def response_media_type?(value)
          value.is_a?(Symbol) && RESPONSE_MEDIA_TYPES.include?(value)
        end

        def normalize_response_body(description, data:, example:, examples:, options:)
          return [data && ActionSpec::Schema.from_definition(data), example, examples] if data || example || examples
          return [nil, nil, options.presence] if options.present?
          return [nil, nil, nil] if description.is_a?(String) || description.nil?

          parsed_schema = ActionSpec::Schema.schema_definition?(description) ? ActionSpec::Schema.from_definition(description) : nil
          return [parsed_schema, nil, nil] if parsed_schema

          [nil, description, options.presence]
        end

        def resolved_description(description, desc)
          return description if description.is_a?(String)
          return desc if desc.present?

          nil
        end

        def add_param(location_name, name, type, required:, **options)
          required ||= options.delete(:required) == true
          endpoint.request.add_param(
            location_name,
            ActionSpec::Schema.build_field(name, options.merge(type:), required:, scopes: scopes.dup)
          )
        end

        def add_many(location_name, params, required:)
          params.each_pair do |name, definition|
            endpoint.request.add_param(
              location_name,
              ActionSpec::Schema.build_field(name, definition, required:, scopes: scopes.dup)
            )
          end
        end

        def add_body(media_type, definition, required:)
          endpoint.request.require_body! if required
          ActionSpec::Schema.build_fields(definition, scopes: scopes.dup).each_value do |field|
            endpoint.request.add_body(media_type, field)
          end
        end
    end
  end
end
