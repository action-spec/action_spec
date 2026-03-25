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

      alias error response

      private

        attr_reader :endpoint
        attr_reader :scopes

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
