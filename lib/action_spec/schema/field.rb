# frozen_string_literal: true

module ActionSpec
  module Schema
    class Field
      attr_reader :name, :schema

      def initialize(name:, required:, schema:)
        @name = name.to_sym
        @required = required
        @schema = schema
      end

      def required?
        @required
      end

      def default_value
        schema.default
      end

      def copy
        self.class.new(name:, required: required?, schema: schema.copy)
      end
    end
  end
end
