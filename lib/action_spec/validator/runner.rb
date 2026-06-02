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
        merge_body!(result)
        merge_group!(result, endpoint.request.header, source: header_source, location: :headers)
        merge_group!(result, endpoint.request.cookie, source: cookie_source, location: :cookies)
        result.apply_scope_options!(endpoint.request.scope_options)
        apply_custom_validations!(result)
        result
      end

      private

        attr_reader :endpoint, :controller, :coerce

        def merge_body!(result)
          if endpoint.request.body_required? && body_source.blank?
            result.add_error("body", :required)
            return
          end

          merge_group!(result, endpoint.request.body, source: body_source, location: :body)
        end

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

        def body_source
          return params_source unless controller.request.respond_to?(:request_parameters)

          controller.request.request_parameters || {}
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
          return field.output_name if field.px_key.present?
          return field.name.to_s.tr("_", "-").downcase if location == :headers

          field.name
        end

        def apply_custom_validations!(result)
          return unless endpoint.request.custom_validation?

          with_controller_px(result.px) do
            endpoint.request.custom_validation_locations.each do |group|
              location = group.name
              validate_group!(
                result,
                group,
                values: result.px.scope.fetch(location),
                location:
              )
            end
          end
        end

        def validate_group!(result, group, values:, location:)
          return unless group.custom_validation?

          group.custom_validation_fields.each do |field|
            key = storage_key(field, location)
            next unless values.key?(key)

            validate_field!(field, values[key], result:, path: [field.name])
          end
        end

        def validate_field!(field, value, result:, path:)
          validate_nested_schema!(field.schema, value, result:, path:)
          return if field.validate_value(value, context: controller)

          field.add_error(result, path:, type: :invalid, value:, context: controller)
        end

        def validate_nested_schema!(schema, value, result:, path:)
          return unless schema.custom_validation?

          case schema
          when ActionSpec::Schema::ObjectOf
            return unless value.is_a?(Hash)

            source = value.with_indifferent_access
            schema.custom_validation_fields.each do |field|
              next unless source.key?(field.output_name)

              validate_field!(field, source[field.output_name], result:, path: [*path, field.name])
            end
          when ActionSpec::Schema::ArrayOf
            return unless value.is_a?(Array)

            value.each_with_index do |entry, index|
              validate_array_item!(schema.item, entry, result:, path: [*path, index])
            end
          end
        end

        def validate_array_item!(schema, value, result:, path:)
          return unless schema.custom_validation?

          case schema
          when ActionSpec::Schema::ObjectOf
            return unless value.is_a?(Hash)

            source = value.with_indifferent_access
            schema.custom_validation_fields.each do |field|
              next unless source.key?(field.output_name)

              validate_field!(field, source[field.output_name], result:, path: [*path, field.name])
            end
          when ActionSpec::Schema::ArrayOf
            return unless value.is_a?(Array)

            value.each_with_index do |entry, index|
              validate_array_item!(schema.item, entry, result:, path: [*path, index])
            end
          end
        end

        def with_controller_px(px)
          previous_defined = controller.instance_variable_defined?(:@px)
          previous = controller.instance_variable_get(:@px)
          controller.instance_variable_set(:@px, px)
          yield
        ensure
          if previous_defined
            controller.instance_variable_set(:@px, previous)
          else
            controller.remove_instance_variable(:@px) if controller.instance_variable_defined?(:@px)
          end
        end
    end
  end
end
