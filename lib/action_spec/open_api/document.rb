# frozen_string_literal: true

module ActionSpec
  module OpenApi
    class Document
      OPENAPI_VERSION = "3.2.0"

      def initialize(title:, version:, server_url: nil)
        @title = title
        @version = version
        @server_url = server_url
      end

      def build(paths:)
        {
          "openapi" => OPENAPI_VERSION,
          "info" => {
            "title" => title,
            "version" => version
          },
          "paths" => paths
        }.tap do |document|
          document["servers"] = [{ "url" => server_url }] if server_url.present?
        end
      end

      private

        attr_reader :title, :version, :server_url
    end
  end
end
