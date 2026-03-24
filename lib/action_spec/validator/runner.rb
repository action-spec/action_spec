# frozen_string_literal: true

module ActionSpec
  module Validator
    class Runner
      def initialize(endpoint:, controller:, coerce:)
        @endpoint = endpoint
        @controller = controller
        @coerce = coerce
      end

      def call
        result = ValidationResult.new
        merge_group!(result, endpoint.request.path, source: path_source, location: :path)
        merge_group!(result, endpoint.request.query, source: params_source, location: :query)
        merge_group!(result, endpoint.request.body, source: params_source, location: :body)
        merge_group!(result, endpoint.request.header, source: header_source, location: :headers)
        merge_group!(result, endpoint.request.cookie, source: cookie_source, location: :cookies)
        result
      end

      private

        attr_reader :endpoint, :controller, :coerce

        def merge_group!(result, group, source:, location:)
          group.fields.each do |field|
            value = resolve_field(field, result:, source:, location:)
            next if value.equal?(ActionSpec::Schema::Missing)

            result.assign(location, storage_key(field, location), value, scopes: field.scopes)
          end
        end

        def resolve_field(field, result:, source:, location:)
          raw_source = location == :headers ? normalize_headers(source) : source
          field_source = raw_source.is_a?(Hash) ? raw_source.with_indifferent_access : raw_source
          ActionSpec::Schema::Resolver.new(
            field:,
            source: field_source,
            context: controller,
            coerce:,
            result:,
            path: []
          ).resolve
        end

        def params_source
          controller.params.to_unsafe_h
        end

        def path_source
          controller.request.path_parameters.except(:controller, :action)
        end

        def header_source
          controller.request.headers.to_h
        end

        def cookie_source
          return {} unless controller.respond_to?(:cookies, true)

          controller.send(:cookies).to_hash
        end

        def normalize_headers(headers)
          headers.each_with_object(HeaderHash.new) do |(key, value), normalized|
            normalized[key] = value
          end
        end

        def storage_key(field, location)
          return field.name.to_s.tr("_", "-").downcase if location == :headers

          field.name
        end
    end
  end
end
