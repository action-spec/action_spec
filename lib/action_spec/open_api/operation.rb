# frozen_string_literal: true

module ActionSpec
  module OpenApi
    class Operation
      def initialize(endpoint)
        @endpoint = endpoint
        @schema = Schema.new
      end

      def build
        {
          "summary" => endpoint.summary.presence,
          "parameters" => parameters.presence,
          "requestBody" => schema.request_body(endpoint.request),
          "responses" => responses
        }.compact
      end

      private

        attr_reader :endpoint, :schema

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
