# frozen_string_literal: true

require "spec_helper"

RSpec.describe ActionSpec::Validator do
  include_context "with reset ActionSpec config"

  it "collects enum, pattern, and range errors together" do
    ActionSpec.configure do |config|
      config.rescue_invalid_parameters = false
    end

    controller = build_controller do
      before_action :validate_and_coerce_params!

      doc :create do
        query :status, String, enum: %w[draft published]
        query :slug, String, pattern: /\A[a-z\-]+\z/
        query :score, Integer, range: { ge: 1, le: 5 }
      end

      def create
        head :ok
      end
    end

    expect do
      dispatch(
        controller,
        action: :create,
        method: "POST",
        path: "/users",
        params: {
          status: "archived",
          slug: "Bad Slug",
          score: "8"
        }
      )
    end.to raise_error(ActionSpec::InvalidParameters) { |error|
      expect(error.errors.attribute_names).to include(:status, :slug, :score)
    }
  end

  it "raises a bad request error when validation fails" do
    ActionSpec.configure do |config|
      config.rescue_invalid_parameters = false
    end

    controller = build_controller do
      before_action :validate_and_coerce_params!

      doc :create do
        query! :page, Integer
        json data: {
          name!: String,
          rate!: { type: Integer, range: { ge: 1, le: 5 } }
        }
      end

      def create
        head :ok
      end
    end

    expect do
      dispatch(
        controller,
        action: :create,
        method: "POST",
        path: "/users",
        params: {
          name: "Tom",
          rate: "8"
        }
      )
    end.to raise_error(ActionSpec::InvalidParameters, /page/i)
  end

  it "builds ActiveModel::Errors with i18n and configurable messages" do
    I18n.backend.store_translations(
      :en,
      activemodel: {
        errors: {
          messages: {
            required: "must be provided",
            invalid_type: "must be a valid %{expected}"
          }
        }
      }
    )

    ActionSpec.configure do |config|
      config.rescue_invalid_parameters = false
      config.error_messages[:invalid_type] = ->(_attribute, options) { "should be coercible to #{options.fetch(:expected)}" }
    end

    controller = build_controller do
      before_action :validate_and_coerce_params!

      doc :create do
        query! :page, Integer
        json data: { birthday!: Date }
      end

      def create
        head :ok
      end
    end

    expect do
      dispatch(
        controller,
        action: :create,
        method: "POST",
        path: "/users",
        params: { birthday: "not-a-date" }
      )
    end.to raise_error(ActionSpec::InvalidParameters) { |error|
      expect(error.errors.attribute_names).to include(:page, :birthday)
      expect(error.errors.full_messages).to include("Page must be provided")
      expect(error.errors.full_messages).to include("Birthday should be coercible to date")
    }
  end
end
