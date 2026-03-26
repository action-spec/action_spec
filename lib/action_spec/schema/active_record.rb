# frozen_string_literal: true

module ActionSpec
  module Schema
    module ActiveRecord
      extend ActiveSupport::Concern

      class_methods do
        def schemas(only: nil, except: nil, on: nil, required: nil, merge: nil, bang: true)
          names = selected_column_names(only:, except:)
          @action_spec_validator_index = build_validator_index
          @action_spec_validation_context = normalize_validation_context(on)
          @action_spec_required_override = normalize_required_override(required)
          @action_spec_schema_merge = normalize_schema_merge(merge)

          names.each_with_object(ActiveSupport::OrderedHash.new) do |name, hash|
            base_required = required_output?(name)
            definition = schema_definition_for(name, bang:, required: base_required)
            definition = merge_definition_for(name, definition)
            output_required = output_required_for(definition, bang:, fallback: base_required)
            definition = normalize_required_in_definition(definition, bang:, required: output_required)
            hash[output_name(name, bang:, required: output_required)] = definition
          end
        ensure
          remove_instance_variable(:@action_spec_validator_index) if instance_variable_defined?(:@action_spec_validator_index)
          remove_instance_variable(:@action_spec_validation_context) if instance_variable_defined?(:@action_spec_validation_context)
          remove_instance_variable(:@action_spec_required_override) if instance_variable_defined?(:@action_spec_required_override)
          remove_instance_variable(:@action_spec_schema_merge) if instance_variable_defined?(:@action_spec_schema_merge)
        end

        private

          def selected_column_names(only:, except:)
            selected = selected_names(only)
            excluded = excluded_names(except)

            column_names.select { |name| selected.include?(name) && !excluded.include?(name) }
          end

          def selected_names(only)
            Array(only).presence&.map { |name| normalize_name(name) } || column_names
          end

          def excluded_names(except)
            Array(except).map { |name| normalize_name(name) }
          end

          def output_name(name, bang:, required:)
            (bang && required ? "#{name}!" : name).to_sym
          end

          def schema_definition_for(name, bang:, required:)
            definition = { type: schema_type_for(name) }
            definition[:required] = true if required && !bang
            definition[:allow_blank] = false if blank_disallowed_by_validation?(name)
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
            database_required?(name) || presence_requires_value?(name)
          end

          def database_required?(name)
            !column_nullable?(name) && column_default_for(name).nil?
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
            validators_for(name, ActiveModel::Validations::NumericalityValidator).each_with_object({}) do |validator, range|
              options = validator.options
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

              validators_for(name, ActiveModel::Validations::LengthValidator).each do |validator|
                options = validator.options
                length[:minimum] = options[:minimum] if options.key?(:minimum)
                length[:maximum] = options[:maximum] if options.key?(:maximum)

                if options.key?(:is)
                  length[:minimum] = options[:is]
                  length[:maximum] = options[:is]
                end
              end
            end

            definition.presence
          end

          def string_limit_for(name)
            column = columns_hash.fetch(name)
            return unless column.type.in?([:string, :text])

            column.limit
          end

          def blank_disallowed_by_validation?(name)
            validator = presence_validator_for(name)
            validator.present? && !validator_allows_blank?(validator)
          end

          def presence_requires_value?(name)
            validator = presence_validator_for(name)
            validator.present? && !validator_allows_blank?(validator) && !validator_allows_nil?(validator)
          end

          def presence_validator_for(name)
            validator_for(name, ActiveModel::Validations::PresenceValidator)
          end

          def validator_allows_blank?(validator)
            validator.options[:allow_blank] == true
          end

          def validator_allows_nil?(validator)
            validator.options[:allow_nil] == true
          end

          def validator_for(name, klass)
            validators_for(name, klass).first
          end

          def validators_for(name, klass)
            validator_index.fetch(name.to_s, []).select do |validator|
              validator.is_a?(klass) && static_validator?(validator)
            end
          end

          def static_validator?(validator)
            %i[if unless].none? { |option| validator.options.key?(option) } &&
              validation_context_matches?(validator)
          end

          def validation_context_matches?(validator)
            return false if requested_validation_context.nil? && validator.options.key?(:on)
            return false if requested_validation_context.nil? && validator.options.key?(:except_on)

            matches_validation_context?(validator) && allowed_by_except_on?(validator)
          end

          def matches_validation_context?(validator)
            return true unless validator.options.key?(:on)

            validator_contexts_for(validator.options[:on]).include?(requested_validation_context)
          end

          def allowed_by_except_on?(validator)
            return true unless validator.options.key?(:except_on)

            !validator_contexts_for(validator.options[:except_on]).include?(requested_validation_context)
          end

          def validator_contexts_for(value)
            Array(value).filter_map { |entry| normalize_validation_context(entry) }
          end

          def normalize_validation_context(value)
            value.present? ? value.to_sym : nil
          end

          def requested_validation_context
            @action_spec_validation_context
          end

          def required_output?(name)
            override = @action_spec_required_override
            return required_attribute?(name) if override.nil?
            return override if override == true || override == false

            override.include?(name.to_s)
          end

          def normalize_required_override(value)
            return if value.nil?
            return value if value == true || value == false

            Array(value).map { |name| normalize_name(name) }
          end

          def merge_definition_for(name, definition)
            fragment = @action_spec_schema_merge.fetch(name.to_s, nil)
            return definition unless fragment

            definition.deep_merge(fragment)
          end

          def output_required_for(definition, bang:, fallback:)
            return fallback if bang && !definition.key?(:required)

            definition.fetch(:required, fallback) == true
          end

          def normalize_required_in_definition(definition, bang:, required:)
            definition = definition.deep_dup
            if bang
              definition.delete(:required)
            else
              required ? definition[:required] = true : definition.delete(:required)
            end
            definition
          end

          def normalize_schema_merge(value)
            return {} if value.nil?

            value.to_h.each_with_object({}) do |(name, fragment), hash|
              hash[normalize_name(name)] = normalize_schema_fragment(fragment)
            end
          end

          def normalize_schema_fragment(fragment)
            fragment.to_h.deep_symbolize_keys
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
