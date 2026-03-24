# frozen_string_literal: true

module ActionSpec
  class HeaderHash < ActiveSupport::HashWithIndifferentAccess
    private

      def convert_key(key)
        super.to_s.sub(/\AHTTP_/, "").tr("_", "-").downcase
      end
  end
end
