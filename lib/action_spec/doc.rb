# frozen_string_literal: true

require "action_spec/doc/endpoint"
require "action_spec/doc/dsl"

module ActionSpec
  module Doc
    extend ActiveSupport::Concern

    class_methods do
      DryEntry = Struct.new(:block, :options, keyword_init: true)

      def action_specs
        @action_specs ||= begin
          parent = superclass.respond_to?(:action_specs) ? superclass.action_specs : {}
          parent.transform_values(&:copy)
        end
      end

      def dry_blocks
        @dry_blocks ||= begin
          parent = superclass.respond_to?(:dry_blocks) ? superclass.dry_blocks : {}
          parent.transform_values do |entries|
            entries.map { |entry| DryEntry.new(block: entry.block, options: entry.options.deep_dup) }
          end
        end
      end

      def doc(action_or_summary = nil, summary = nil, **options, &block)
        action_name, endpoint_summary = normalize_doc_arguments(action_or_summary, summary)
        action_name ||= infer_action_name(caller_locations(1, 1).first)
        endpoint = Endpoint.new(action_name, summary: endpoint_summary, options: {})
        endpoint = apply_dry_blocks(endpoint)
        endpoint.options.merge!(options)
        action_specs[action_name.to_sym] = endpoint.apply(block || proc {})
      end

      def doc_dry(actions = :all, **options, &block)
        Array(actions).each do |action|
          (dry_blocks[action.to_sym] ||= []) << DryEntry.new(block:, options:)
        end
      end
      alias api_dry doc_dry

      def action_spec_for(action)
        action_specs[action.to_sym]
      end

      private

        def normalize_doc_arguments(action_or_summary, summary)
          return [action_or_summary, summary] if action_or_summary.is_a?(Symbol)

          [nil, action_or_summary]
        end

        def apply_dry_blocks(endpoint)
          [*dry_blocks[:all], *dry_blocks[endpoint.action]].compact.each do |entry|
            endpoint.options.merge!(entry.options)
            endpoint.apply(entry.block) if entry.block
          end
          endpoint
        end

        def infer_action_name(location)
          file = location.absolute_path || location.path
          lines = File.readlines(file)
          method_definition = lines[(location.lineno - 1)..].find { |line| line.match?(/^\s*def\s+(?!self\.)/) }
          return Regexp.last_match(1).to_sym if method_definition&.match(/^\s*def\s+([a-zA-Z_]\w*[!?=]?)/)

          raise ArgumentError, "ActionSpec could not infer the target action for `doc`; use `doc :action` instead"
        end
    end
  end
end
