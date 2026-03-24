# frozen_string_literal: true

require "spec_helper"

RSpec.describe ActionSpec::Validator do
  include_context "with reset ActionSpec config"

  it "coerces array item types through the runtime validator" do
    controller = build_controller do
      doc :create do
        json data: {
          tags!: [Integer]
        }
      end

      def create; end
    end

    request = Struct.new(:path_parameters, :headers).new({}, {})
    params = ActionController::Parameters.new(tags: %w[1 2 3])
    runner_controller = Struct.new(:params, :request).new(params, request)

    result = ActionSpec::Validator::Runner.new(
      endpoint: controller.action_spec_for(:create),
      controller: runner_controller,
      coerce: true
    ).call

    expect(result.errors).to be_empty
    px = result.px

    expect(px[:tags]).to eq([1, 2, 3])
  end

  it "records nested and array-item validation failures with precise attribute paths" do
    ActionSpec.configure do |config|
      config.rescue_invalid_parameters = false
    end

    controller = build_controller do
      before_action :validate_and_coerce_params!

      doc :create do
        json data: {
          tags!: [Integer],
          profile!: {
            nickname!: String
          }
        }
      end

      def create
        head :ok
      end
    end

    request = Struct.new(:path_parameters, :headers).new({}, {})
    params = ActionController::Parameters.new(
      tags: [ "1", "bad" ],
      profile: {}
    )
    runner_controller = Struct.new(:params, :request).new(params, request)

    result = ActionSpec::Validator::Runner.new(
      endpoint: controller.action_spec_for(:create),
      controller: runner_controller,
      coerce: true
    ).call

    expect(result.errors.attribute_names).to include(:"tags.1", :"profile.nickname")
  end

  it "applies proc defaults only when the value is missing" do
    controller = build_controller do
      doc :create do
        query :page, Integer, default: -> { 3 }
      end

      def create; end
    end

    request = Struct.new(:path_parameters, :headers).new({}, {})
    params = ActionController::Parameters.new
    runner_controller = Struct.new(:params, :request).new(params, request)

    result = ActionSpec::Validator::Runner.new(
      endpoint: controller.action_spec_for(:create),
      controller: runner_controller,
      coerce: true
    ).call

    expect(result.errors).to be_empty
    px = result.px

    expect(px[:page]).to eq(3)
  end
end
