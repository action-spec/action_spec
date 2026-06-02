# frozen_string_literal: true

module ActionSpec
  module Doc
    class Endpoint
      attr_reader :action, :summary, :options, :request, :responses

      def initialize(action, summary: nil, options: {})
        @action = action.to_sym
        @summary = summary
        @options = options
        @request = Request.new
        @responses = {}
      end

      def dsl
        @dsl ||= Dsl.new(self)
      end

      def apply(block)
        dsl.instance_exec(&block)
        self
      end

      def add_response(code, response)
        existing = @responses[code.to_s]
        @responses[code.to_s] = existing ? existing.merge(response) : response
      end

      def copy
        self.class.new(action, summary:, options: options.deep_dup).tap do |endpoint|
          endpoint.request.replace_with(request.copy)
          responses.each do |code, response|
            endpoint.add_response(code, response.copy)
          end
        end
      end
    end

    class Request
      attr_reader :header, :path, :query, :cookie, :body, :body_media_types, :scope_options

      def initialize
        @header = Location.new(:header)
        @path = Location.new(:path)
        @query = Location.new(:query)
        @cookie = Location.new(:cookie)
        @body = Location.new(:body)
        @body_media_types = {}
        @scope_options = ActiveSupport::HashWithIndifferentAccess.new
        @body_required = false
      end

      def location(name)
        public_send(name)
      end

      def add_param(location_name, field)
        location(location_name).add(field)
        clear_custom_validation_cache!
      end

      def add_body(media_type, field)
        body.add(field)
        (@body_media_types[media_type.to_sym] ||= Location.new(media_type.to_sym)).add(field.copy)
        clear_custom_validation_cache!
      end

      def register_scope(name, compact: nil, compact_blank: nil)
        key = name.to_sym
        @scope_options[key] = scope_options.fetch(key, {}).merge(
          {
            compact:,
            compact_blank:
          }.compact
        )
      end

      def require_body!
        @body_required = true
      end

      def body_required?
        @body_required
      end

      def replace_with(other)
        @header = other.header
        @path = other.path
        @query = other.query
        @cookie = other.cookie
        @body = other.body
        @body_media_types = other.body_media_types
        @scope_options = other.scope_options
        @body_required = other.body_required?
        clear_custom_validation_cache!
      end

      def copy
        self.class.new.tap do |request|
          request.instance_variable_set(:@header, header.copy)
          request.instance_variable_set(:@path, path.copy)
          request.instance_variable_set(:@query, query.copy)
          request.instance_variable_set(:@cookie, cookie.copy)
          request.instance_variable_set(:@body, body.copy)
          request.instance_variable_set(
            :@body_media_types,
            body_media_types.transform_values(&:copy)
          )
          request.instance_variable_set(:@scope_options, scope_options.deep_dup)
          request.instance_variable_set(:@body_required, body_required?)
        end
      end

      def custom_validation?
        custom_validation_locations.any?
      end

      def custom_validation_locations
        @custom_validation_locations ||= [header, path, query, cookie, body].select(&:custom_validation?).freeze
      end

      private

        def clear_custom_validation_cache!
          remove_instance_variable(:@custom_validation_locations) if instance_variable_defined?(:@custom_validation_locations)
        end
    end

    class Location
      include Enumerable

      attr_reader :name

      def initialize(name)
        @name = name
        @fields = ActiveSupport::OrderedHash.new
      end

      def add(field)
        @fields[field.name] = field
        clear_custom_validation_cache!
      end

      def field(name)
        @fields[name.to_sym]
      end

      def [](name)
        field(name)
      end

      def fields
        @fields.values
      end

      def each(&block)
        fields.each(&block)
      end

      def copy
        self.class.new(name).tap do |location|
          fields.each { |field| location.add(field.copy) }
        end
      end

      def custom_validation?
        custom_validation_fields.any?
      end

      def custom_validation_fields
        @custom_validation_fields ||= fields.select(&:custom_validation?).freeze
      end

      private

        def clear_custom_validation_cache!
          remove_instance_variable(:@custom_validation_fields) if instance_variable_defined?(:@custom_validation_fields)
      end
    end

    class Response
      attr_reader :code, :description, :media_types, :options

      def initialize(code:, description:, media_type:, schema: nil, example: nil, examples: nil, options:)
        @code = code.to_s
        @description = description
        @media_types = ActiveSupport::OrderedHash.new
        @options = options.deep_dup
        merge_media_type!(media_type || :json, schema:, example:, examples:, initialize: true)
      end

      def merge(other)
        copy.tap do |merged|
          merged.instance_variable_set(:@description, other.description.presence || description)
          merged.instance_variable_set(:@options, options.deep_dup.merge(other.options.deep_dup))
          other.media_types.each do |media_type, content|
            merged.send(:merge_media_type!, media_type, **merged.send(:copy_content, content))
          end
        end
      end

      def copy
        self.class.new(
          code:,
          description:,
          media_type: nil,
          schema: nil,
          example: nil,
          examples: nil,
          options: options.deep_dup
        ).tap do |response|
          response.instance_variable_set(
            :@media_types,
            media_types.each_with_object(ActiveSupport::OrderedHash.new) do |(media_type, content), hash|
              hash[media_type] = copy_content(content)
            end
          )
        end
      end

      private

        def merge_media_type!(media_type, schema:, example:, examples:, initialize: false)
          content = (@media_types[media_type.to_sym] ||= {
            schema: nil,
            example: nil,
            examples: ActiveSupport::OrderedHash.new
          })
          content[:schema] = schema || content[:schema]

          if examples.present?
            convert_example_into_default_example!(content)
            content[:examples].merge!(normalize_examples(examples))
          elsif !example.nil?
            if content[:examples].present? && !initialize
              content[:examples]["default"] ||= example
            else
              content[:example] = example
            end
          end
        end

        def convert_example_into_default_example!(content)
          return if content[:example].nil?

          content[:examples]["default"] ||= content[:example]
          content[:example] = nil
        end

        def normalize_examples(examples)
          examples.each_with_object(ActiveSupport::OrderedHash.new) do |(name, value), hash|
            hash[name.to_s] = value
          end
        end

        def copy_content(content)
          {
            schema: content[:schema]&.copy,
            example: content[:example].deep_dup,
            examples: content[:examples].deep_dup
          }
        end
    end
  end
end
