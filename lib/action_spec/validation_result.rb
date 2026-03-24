# frozen_string_literal: true

module ActionSpec
  class ValidationResult
    extend ActiveModel::Naming
    extend ActiveModel::Translation

    attr_reader :errors, :px

    def initialize
      @errors = ActiveModel::Errors.new(self)
      @px = ActiveSupport::HashWithIndifferentAccess.new(
        path: ActiveSupport::HashWithIndifferentAccess.new,
        query: ActiveSupport::HashWithIndifferentAccess.new,
        body: ActiveSupport::HashWithIndifferentAccess.new,
        headers: HeaderHash.new,
        cookies: ActiveSupport::HashWithIndifferentAccess.new
      )
    end

    def invalid?
      errors.any?
    end

    def assign(location, key, value)
      bucket(location)[key] = value
      px[key] = value if root_bucket?(location)
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

      def bucket(location)
        px.fetch(location)
      end

      def root_bucket?(location)
        %i[path query body].include?(location)
      end
  end
end
