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
        @responses[code.to_s] = response
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
      attr_reader :header, :path, :query, :cookie, :body, :body_media_types

      def initialize
        @header = Location.new(:header)
        @path = Location.new(:path)
        @query = Location.new(:query)
        @cookie = Location.new(:cookie)
        @body = Location.new(:body)
        @body_media_types = {}
        @body_required = false
      end

      def location(name)
        public_send(name)
      end

      def add_param(location_name, field)
        location(location_name).add(field)
      end

      def add_body(media_type, field)
        body.add(field)
        (@body_media_types[media_type.to_sym] ||= Location.new(media_type.to_sym)).add(field.copy)
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
        @body_required = other.body_required?
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
          request.instance_variable_set(:@body_required, body_required?)
        end
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
    end

    class Response
      attr_reader :code, :description, :media_type, :options

      def initialize(code:, description:, media_type:, options:)
        @code = code.to_s
        @description = description
        @media_type = media_type
        @options = options
      end

      def copy
        self.class.new(code:, description:, media_type:, options: options.deep_dup)
      end
    end
  end
end
