# frozen_string_literal: true

module ActionSpec
  module OpenApi
    class Generator
      class << self
        def generate!(application: nil, routes: nil, output:, title: nil, version: nil, server_url: nil)
          document = new(application:, routes:, title:, version:, server_url:).call

          FileUtils.mkdir_p(File.dirname(output))
          File.write(output, YAML.dump(document))
        end
      end

      def initialize(application: nil, routes: nil, title: nil, version: nil, server_url: nil)
        @application = application
        @routes = routes
        @title = title
        @version = version
        @server_url = server_url
      end

      def call
        Document.new(
          title: resolved_title,
          version: resolved_version,
          server_url:
        ).build(paths:)
      end

      private

        attr_reader :application, :routes, :title, :version, :server_url

        def resolved_title
          return title if title.present?

          application_name = application&.class&.name.to_s.sub(/::Application\z/, "").sub(/Application\z/, "")
          application_name.demodulize.titleize.presence || "API"
        end

        def resolved_version
          version.presence || "1.0.0"
        end

        def paths
          route_definitions.each_with_object(ActiveSupport::OrderedHash.new) do |route, hash|
            next unless (controller = controller_for(route))
            next unless controller.respond_to?(:action_spec_for)
            next unless (endpoint = controller.action_spec_for(route_action(route)))
            next if endpoint.options[:openapi] == false

            path = normalized_path(route)
            next if path.blank?

            hash[path] ||= ActiveSupport::OrderedHash.new
            route_verbs(route).each do |verb|
              hash[path][verb] = Operation.new(endpoint).build
            end
          end
        end

        def route_definitions
          return routes if routes

          application.routes.routes
        end

        def controller_for(route)
          controller_name = route_defaults(route)[:controller].presence
          return unless controller_name

          "#{controller_name.camelize}Controller".safe_constantize
        end

        def route_action(route)
          route_defaults(route).fetch(:action).to_sym
        end

        def route_defaults(route)
          defaults =
            if route.respond_to?(:defaults)
              route.defaults
            elsif route.respond_to?(:requirements)
              route.requirements
            else
              route[:defaults]
            end

          defaults.to_h.symbolize_keys
        end

        def route_verbs(route)
          raw_verb =
            if route.respond_to?(:verb) && route.verb.respond_to?(:source)
              route.verb.source
            elsif route.respond_to?(:verb)
              route.verb.to_s
            else
              route[:verb].to_s
            end

          raw_verb.gsub(/[$^]/, "").split("|").filter_map { |verb| verb.presence&.downcase }
        end

        def normalized_path(route)
          raw_path =
            if route.respond_to?(:path) && route.path.respond_to?(:spec)
              route.path.spec.to_s
            elsif route.respond_to?(:path)
              route.path.to_s
            else
              route[:path].to_s
            end

          raw_path
            .sub(/\(\.:format\)\z/, "")
            .gsub(/:(\w+)/, '{\1}')
        end
    end
  end
end
