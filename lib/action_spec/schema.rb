# frozen_string_literal: true

require "action_spec/schema/base"
require "action_spec/schema/field"
require "action_spec/schema/scalar"
require "action_spec/schema/object_of"
require "action_spec/schema/array_of"
require "action_spec/schema/active_record"
require "action_spec/schema/resolver"
require "action_spec/schema/type_caster"

module ActionSpec
  module Schema
    Missing = Object.new.freeze
    OPTION_KEYS = %i[default desc enum range pattern length blank allow_blank example examples].freeze
    FIELD_OPTION_KEYS = (OPTION_KEYS + %i[required]).freeze

    class << self
      def build(type = nil, **options)
        definition = options.symbolize_keys
        definition[:type] = type if type
        from_definition(definition)
      end

      def build_field(name, definition = nil, required: false, scopes: [])
        Field.new(
          name: field_name(name),
          required: required_key?(name) || required || explicit_required?(definition),
          schema: build_field_schema(strip_field_options(definition)),
          scopes:
        )
      end

      def from_definition(definition)
        return Scalar.new(String) if definition.blank?
        return ArrayOf.new(from_definition(type: definition.first)) if definition.is_a?(Array) && definition.one?
        return ArrayOf.new(from_definition(type: nil)) if definition == []
        return Scalar.new(definition) unless definition.is_a?(Hash)

        definition = definition.deep_symbolize_keys
        if definition.key?(:type)
          type = definition[:type]
          options = definition.except(:type)
          return ArrayOf.new(from_definition(type: type.first), options) if type.is_a?(Array) && type.one?
          return ObjectOf.new(build_fields(definition.except(:type, *OPTION_KEYS))) if type == Object && definition.except(:type, *OPTION_KEYS).present?

          return Scalar.new(type, options)
        end

        ObjectOf.new(build_fields(definition))
      end

      def build_fields(definition_hash, scopes: [])
        definition_hash.each_with_object(ActiveSupport::OrderedHash.new) do |(name, definition), fields|
          field = build_field(name, definition, scopes:)
          fields[field.name] = field
        end
      end

      def field_name(name)
        name.to_s.delete_suffix("!").to_sym
      end

      def required_key?(name)
        name.to_s.end_with?("!")
      end

      def build_field_schema(definition)
        return from_definition(type: definition) unless definition.is_a?(Hash)

        definition = definition.symbolize_keys
        return from_definition(definition.except(:required)) if definition.key?(:type)
        return from_definition(definition.except(:required)) if (definition.keys - FIELD_OPTION_KEYS).present?

        from_definition(definition.except(:required).merge(type: String))
      end

      def schema_definition?(definition)
        case definition
        when Array
          definition.one? && schema_definition?(definition.first)
        when Hash
          definition = definition.with_indifferent_access
          return true if definition.key?(:type)
          return true if definition.keys.all? { |key| FIELD_OPTION_KEYS.include?(key.to_sym) }

          definition.any? do |name, value|
            required_key?(name) || schema_definition?(value)
          end
        when Class
          true
        when Symbol
          definition == :boolean || definition == :file || definition == :object
        else
          false
        end
      end

      private

        def explicit_required?(definition)
          definition.is_a?(Hash) && definition.symbolize_keys[:required] == true
        end

        def strip_field_options(definition)
          return definition unless definition.is_a?(Hash)

          definition.symbolize_keys.except(:required)
        end
    end
  end
end
