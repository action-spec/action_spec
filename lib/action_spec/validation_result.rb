# frozen_string_literal: true

module ActionSpec
  class ValidationResult
    extend ActiveModel::Naming
    extend ActiveModel::Translation

    BUILT_IN_SCOPES = %i[path query body headers cookies].freeze

    class << self
      def empty_px
        new.px
      end
    end

    attr_reader :errors, :px

    def initialize
      @errors = ActiveModel::Errors.new(self)
      @px = build_px
    end

    def invalid?
      errors.any?
    end

    def assign(location, key, value, scopes: [])
      bucket(location)[key] = value
      px[key] = value if root_bucket?(location)
      Array(scopes).each { |scope_name| scope_bucket(scope_name)[key] = value }
    end

    def apply_scope_options!(options_by_scope)
      options_by_scope.each do |scope_name, options|
        bucket = px.scope[scope_name]
        next unless bucket

        bucket.compact! if options[:compact]
        bucket.delete_if { |_key, value| value.blank? } if options[:compact_blank]
      end
    end

    def add_error(attribute, type, **options)
      if (message = ActionSpec.config.message_for(attribute, type, options))
        errors.add(attribute, message)
      else
        errors.add(attribute, type, **options)
      end
    end

    def read_attribute_for_validation(_attribute)
      nil
    end

    def self.lookup_ancestors
      [self]
    end

    def self.model_name
      @model_name ||= ActiveModel::Name.new(self, nil, "ActionSpec::Parameters")
    end

    def self.human_attribute_name(attribute, options = {})
      key = attribute.to_s
      defaults = [
        :"activemodel.attributes.#{model_name.i18n_key}.#{key}",
        :"activemodel.attributes.#{model_name.i18n_key}.#{key.tr('.', '_')}",
        key.tr(".", " ").humanize
      ]

      I18n.translate(defaults.shift, **options, default: defaults)
    end

    private

      def build_px
        values = ActiveSupport::HashWithIndifferentAccess.new
        scope = ActiveSupport::HashWithIndifferentAccess.new

        BUILT_IN_SCOPES.each do |scope_name|
          bucket = scope_name == :headers ? HeaderHash.new : ActiveSupport::HashWithIndifferentAccess.new
          values[scope_name] = bucket
          scope[scope_name] = bucket
        end

        # Keep px hash-like while exposing grouped views through px.scope.
        values.instance_variable_set(:@scope, scope)
        values.define_singleton_method(:scope) { @scope }
        values
      end

      def bucket(location)
        px.scope.fetch(location)
      end

      def scope_bucket(name)
        px.scope[name] ||= ActiveSupport::HashWithIndifferentAccess.new
      end

      def root_bucket?(location)
        %i[path query body].include?(location)
      end
  end
end
