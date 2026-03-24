# frozen_string_literal: true

module ActionSpec
  class InvalidParameters < ActionController::BadRequest
    attr_reader :result
    alias parameters result
    delegate :errors, :px, to: :result

    def initialize(result)
      @result = result
      super(result.errors.full_messages.to_sentence.presence || "Invalid parameters")
    end
  end
end
