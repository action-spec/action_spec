# frozen_string_literal: true

module ActionSpec
  module Schema
    module ActiveRecord
      extend ActiveSupport::Concern

      class_methods do
        def schemas(only: nil)
          names = selected_column_names(only)
          @action_spec_validator_index = build_validator_index

          names.each_with_object(ActiveSupport::OrderedHash.new) do |name, hash|
            hash[output_name(name)] = schema_definition_for(name)
          end
        ensure
          remove_instance_variable(:@action_spec_validator_index) if instance_variable_defined?(:@action_spec_validator_index)
        end

        private

          def selected_column_names(only)
            selected = Array(only).presence&.map { |name| normalize_name(name) } || column_names

            column_names.select { |name| selected.include?(name) }
          end

          def output_name(name)
            required_attribute?(name) ? "#{name}!" : name
          end

          def schema_definition_for(name)
            definition = { type: schema_type_for(name) }
            definition[:default] = column_default_for(name) unless column_default_for(name).nil?
            definition[:desc] = column_comment_for(name) if column_comment_for(name).present?
            definition[:enum] = resolved_enum_for(name) if resolved_enum_for(name).present?
            definition[:pattern] = pattern_for(name) if pattern_for(name)
            definition[:range] = range_for(name) if range_for(name).present?
            definition[:length] = length_for(name) if length_for(name).present?
            definition
          end

          def schema_type_for(name)
            return String if enum_values_for(name).present?

            case columns_hash.fetch(name).type
            when :string, :text, :binary then String
            when :integer, :bigint then Integer
            when :float then Float
            when :decimal then BigDecimal
            when :boolean then :boolean
            when :date then Date
            when :datetime, :timestamp then DateTime
            when :time then Time
            when :json, :jsonb then Object
            else String
            end
          end

          def required_attribute?(name)
            (!column_nullable?(name) && column_default_for(name).nil?) || presence_validated?(name)
          end

          def column_nullable?(name)
            columns_hash.fetch(name).null
          end

          def column_default_for(name)
            columns_hash.fetch(name).default
          end

          def column_comment_for(name)
            columns_hash.fetch(name).comment
          end

          def enum_values_for(name)
            defined_enums.fetch(name.to_s, nil)&.keys
          end

          def inclusion_values_for(name)
            validator_for(name, ActiveModel::Validations::InclusionValidator)&.options&.fetch(:in, nil)&.to_a
          end

          def resolved_enum_for(name)
            enum_values_for(name).presence || inclusion_values_for(name).presence
          end

          def pattern_for(name)
            validator_for(name, ActiveModel::Validations::FormatValidator)&.options&.fetch(:with, nil)
          end

          def range_for(name)
            options = validator_for(name, ActiveModel::Validations::NumericalityValidator)&.options
            return if options.blank?

            {}.tap do |range|
              range[:gt] = options[:greater_than] if options.key?(:greater_than)
              range[:ge] = options[:greater_than_or_equal_to] if options.key?(:greater_than_or_equal_to)
              range[:lt] = options[:less_than] if options.key?(:less_than)
              range[:le] = options[:less_than_or_equal_to] if options.key?(:less_than_or_equal_to)
            end.presence
          end

          def length_for(name)
            definition = {}.tap do |length|
              limit = string_limit_for(name)
              length[:maximum] = limit if limit

              options = validator_for(name, ActiveModel::Validations::LengthValidator)&.options || {}
              length[:minimum] = options[:minimum] if options.key?(:minimum)
              length[:maximum] = options[:maximum] if options.key?(:maximum)

              if options.key?(:is)
                length[:minimum] = options[:is]
                length[:maximum] = options[:is]
              end
            end

            definition.presence
          end

          def string_limit_for(name)
            column = columns_hash.fetch(name)
            return unless column.type.in?([:string, :text])

            column.limit
          end

          def presence_validated?(name)
            validator_for(name, ActiveModel::Validations::PresenceValidator).present?
          end

          def validator_for(name, klass)
            validator_index.fetch(name.to_s, []).find { |validator| validator.is_a?(klass) }
          end

          def normalize_name(name)
            name.to_s.delete_suffix("!")
          end

          def build_validator_index
            validators.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |validator, index|
              validator.attributes.each do |attribute|
                index[attribute.to_s] << validator
              end
            end
          end

          def validator_index
            @action_spec_validator_index ||= build_validator_index
          end
      end
    end
  end
end
