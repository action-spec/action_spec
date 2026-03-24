# frozen_string_literal: true

module ActionSpec
  module Schema
    class Field
      attr_reader :name, :schema, :scopes

      def initialize(name:, required:, schema:, scopes: [])
        @name = name.to_sym
        @required = required
        @schema = schema
        @scopes = Array(scopes).map(&:to_sym).freeze
      end

      def required?
        @required
      end

      def default_value
        schema.default
      end

      def copy
        self.class.new(name:, required: required?, schema: schema.copy, scopes:)
      end
    end
  end
end
