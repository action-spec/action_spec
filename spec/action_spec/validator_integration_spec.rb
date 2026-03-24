# frozen_string_literal: true

require "spec_helper"

RSpec.describe "ActionSpec validator integration" do
  around do |example|
    previous = ActionSpec.config.dup
    example.run
  ensure
    ActionSpec.instance_variable_set(:@config, previous)
  end

  it "rescues invalid parameters with the default response" do
    I18n.backend.store_translations(
      :en,
      activemodel: {
        errors: {
          messages: {
            required: "is required",
            invalid_type: "must be a valid %{expected}"
          }
        }
      }
    )

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

    status, headers, body = dispatch(
      controller,
      action: :create,
      method: "POST",
      path: "/users",
      params: { birthday: "not-a-date" }
    )

    expect(status).to eq(400)
    expect(headers["Content-Type"]).to include("application/json")

    payload = json_body(body)
    expect(payload.fetch("errors")).to include(
      "page" => include("Page is required"),
      "birthday" => include("Birthday must be a valid date")
    )
  end

  it "humanizes nested attribute paths through i18n" do
    ActionSpec.configure do |config|
      config.rescue_invalid_parameters = false
    end

    I18n.backend.store_translations(
      :en,
      activemodel: {
        attributes: {
          "action_spec/parameters": {
            "profile.nickname": "Profile nickname"
          }
        }
      }
    )

    controller = build_controller do
      doc :create do
        json data: {
          profile!: {
            nickname!: String
          }
        }
      end

      def create; end
    end

    request = Struct.new(:path_parameters, :headers).new({}, {})
    params = ActionController::Parameters.new(profile: {})
    runner_controller = Struct.new(:params, :request).new(params, request)

    result = ActionSpec::Validator::Runner.new(
      endpoint: controller.action_spec_for(:create),
      controller: runner_controller,
      coerce: true
    ).call

    expect(result.errors.full_messages).to include("Profile nickname is required")
  end
end
