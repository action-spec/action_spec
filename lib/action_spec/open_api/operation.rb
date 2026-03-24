# frozen_string_literal: true

module ActionSpec
  module OpenApi
    class Operation
      def initialize(endpoint, controller_path:)
        @endpoint = endpoint
        @controller_path = controller_path
        @schema = Schema.new
      end

      def build
        {
          "summary" => endpoint.summary.presence,
          "operationId" => operation_id,
          "tags" => tags,
          "parameters" => parameters.presence,
          "requestBody" => schema.request_body(endpoint.request),
          "responses" => responses
        }.compact
      end

      private

        attr_reader :endpoint, :controller_path, :schema

        def tags
          [endpoint.options[:tag].presence || controller_path.presence].compact
        end

        def operation_id
          [primary_tag, endpoint.action].compact.join("_")
        end

        def primary_tag
          resolved_tag&.to_s&.tr("/", "_")
        end

        def resolved_tag
          endpoint.options[:tag].presence || controller_path.presence
        end

        def parameters
          %i[path query header cookie].flat_map do |location|
            endpoint.request.public_send(location).fields.map do |field|
              schema.parameter(field, location:)
            end
          end
        end

        def responses
          return { "200" => { "description" => "OK" } } if endpoint.responses.empty?

          endpoint.responses.each_with_object(ActiveSupport::OrderedHash.new) do |(code, response), hash|
            hash[code] = { "description" => response.description.presence || "OK" }
          end
        end
    end
  end
end
