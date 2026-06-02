# frozen_string_literal: true

module ActionSpec
  module Schema
    class TypeCaster
      class CastError < StandardError
        attr_reader :expected

        def initialize(expected)
          @expected = expected
          super()
        end
      end

      class << self
        def cast(type, value)
          return value if value.nil?

          normalized = normalize(type)
          return cast_object(value) if normalized == :object
          return cast_file(value) if normalized == :file
          return cast_boolean(value) if normalized == :boolean
          return cast_integer(value) if normalized == :integer
          return cast_float(value) if normalized == :float
          return cast_decimal(value) if normalized == :decimal

          active_model_type_for(normalized).cast(value).tap do |casted|
            raise CastError, normalized if casted.nil? && !value.nil?
          end
        end

        def normalize(type)
          return :boolean if boolean_type?(type)
          return :string if type == String
          return :integer if type == Integer
          return :float if type == Float
          return :decimal if type == BigDecimal
          return :date if type == Date
          return :datetime if [DateTime, ActiveSupport::TimeWithZone].include?(type)
          return :time if type == Time
          return :string if type == Symbol
          return :file if type == File
          return :object if [Hash, Object].include?(type)

          type
        end

        private

          def active_model_type_for(type)
            case type
            when :string then ActiveModel::Type::String.new
            when :integer then ActiveModel::Type::Integer.new
            when :float then ActiveModel::Type::Float.new
            when :decimal then ActiveModel::Type::Decimal.new
            when :boolean then ActiveModel::Type::Boolean.new
            when :date then ActiveModel::Type::Date.new
            when :datetime then ActiveModel::Type::DateTime.new
            when :time then ActiveModel::Type::Time.new
            else ActiveModel::Type::Value.new
            end
          end

          def cast_file(value)
            return value if file_like?(value)

            raise CastError, :file
          end

          def cast_object(value)
            return value if value.is_a?(Hash) || value.is_a?(ActionController::Parameters)

            raise CastError, :object
          end

          def cast_integer(value)
            return value if value.is_a?(Integer)
            raise CastError, :integer unless value.is_a?(String) && value.match?(/\A[+-]?\d+\z/)

            active_model_type_for(:integer).cast(value)
          end

          def cast_float(value)
            return value.to_f if value.is_a?(Numeric)
            raise CastError, :float unless value.is_a?(String) && value.match?(/\A[+-]?\d+(\.\d+)?\z/)

            active_model_type_for(:float).cast(value)
          end

          def cast_decimal(value)
            return value if value.is_a?(BigDecimal)
            raise CastError, :decimal unless value.is_a?(Numeric) || (value.is_a?(String) && value.match?(/\A[+-]?\d+(\.\d+)?\z/))

            active_model_type_for(:decimal).cast(value)
          end

          def cast_boolean(value)
            return value if value == true || value == false
            return true if value.in?([1, "1", "true", "t", "yes", "on"])
            return false if value.in?([0, "0", "false", "f", "no", "off"])

            raise CastError, :boolean
          end

          def boolean_type?(type)
            type == :boolean ||
              type.to_s == "boolean" ||
              (Object.const_defined?(:Boolean) && type == ::Boolean)
          end

          def file_like?(value)
            value.is_a?(File) ||
              value.is_a?(Tempfile) ||
              value.respond_to?(:read) ||
              value.is_a?(ActionDispatch::Http::UploadedFile) ||
              (value.is_a?(Hash) && (value.key?(:tempfile) || value.key?("tempfile")))
          end
      end
    end
  end
end
