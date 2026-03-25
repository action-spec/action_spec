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

  it "skips optional missing scalar fields without raising keyword argument errors" do
    controller = build_controller do
      doc :create do
        query :nickname, String
      end

      def create; end
    end

    request = Struct.new(:path_parameters, :headers).new({}, {})
    params = ActionController::Parameters.new
    runner_controller = Struct.new(:params, :request).new(params, request)

    expect do
      result = ActionSpec::Validator::Runner.new(
        endpoint: controller.action_spec_for(:create),
        controller: runner_controller,
        coerce: true
      ).call

      expect(result.errors).to be_empty
      expect(result.px.to_h).not_to have_key("nickname")
    end.not_to raise_error
  end

  it "requires present required values to be non-nil while still allowing blank strings" do
    controller = build_controller do
      doc :create do
        query! :title, String
        query! :published_on, Date
      end

      def create; end
    end

    request = Struct.new(:path_parameters, :headers).new({}, {})
    params = ActionController::Parameters.new(title: "", published_on: nil)
    runner_controller = Struct.new(:params, :request).new(params, request)

    result = ActionSpec::Validator::Runner.new(
      endpoint: controller.action_spec_for(:create),
      controller: runner_controller,
      coerce: true
    ).call

    expect(result.errors.details).to include(published_on: include(error: :required))
    expect(result.errors.attribute_names).not_to include(:title)
    expect(result.px[:title]).to eq("")
    expect(result.px.to_h).not_to have_key("published_on")
  end

  it "rejects explicit nil values for optional fields" do
    controller = build_controller do
      doc :create do
        query :nickname, String
      end

      def create; end
    end

    request = Struct.new(:path_parameters, :headers).new({}, {})
    params = ActionController::Parameters.new(nickname: nil)
    runner_controller = Struct.new(:params, :request).new(params, request)

    result = ActionSpec::Validator::Runner.new(
      endpoint: controller.action_spec_for(:create),
      controller: runner_controller,
      coerce: true
    ).call

    expect(result.errors.details).to include(nickname: include(error: :blank))
    expect(result.px.to_h).not_to have_key("nickname")
  end

  it "rejects blank values when blank is false" do
    controller = build_controller do
      doc :create do
        query :title, String, blank: false
        query :slug, String, allow_blank: false
      end

      def create; end
    end

    request = Struct.new(:path_parameters, :headers).new({}, {})
    params = ActionController::Parameters.new(title: "", slug: "   ")
    runner_controller = Struct.new(:params, :request).new(params, request)

    result = ActionSpec::Validator::Runner.new(
      endpoint: controller.action_spec_for(:create),
      controller: runner_controller,
      coerce: true
    ).call

    expect(result.errors.details).to include(
      title: include(error: :blank),
      slug: include(error: :blank)
    )
  end

  it "treats blank date-like strings as invalid values instead of silently materializing nil" do
    controller = build_controller do
      doc :create do
        query :published_on, Date
        query :published_at, DateTime
        query :published_time, Time
      end

      def create; end
    end

    request = Struct.new(:path_parameters, :headers).new({}, {})
    params = ActionController::Parameters.new(
      published_on: "",
      published_at: "",
      published_time: ""
    )
    runner_controller = Struct.new(:params, :request).new(params, request)

    result = ActionSpec::Validator::Runner.new(
      endpoint: controller.action_spec_for(:create),
      controller: runner_controller,
      coerce: true
    ).call

    expect(result.errors.details).to include(
      published_on: include(error: :invalid_type, expected: :date),
      published_at: include(error: :invalid_type, expected: :datetime),
      published_time: include(error: :invalid_type, expected: :time)
    )
    expect(result.px.to_h).not_to have_key("published_on")
    expect(result.px.to_h).not_to have_key("published_at")
    expect(result.px.to_h).not_to have_key("published_time")
  end

  it "supports required: true without bang syntax" do
    controller = build_controller do
      doc :create do
        query :page, Integer, required: true
        json data: {
          title: { type: String, required: true }
        }
      end

      def create; end
    end

    request = Struct.new(:path_parameters, :headers, :request_parameters).new({}, {}, {})
    params = ActionController::Parameters.new
    runner_controller = Struct.new(:params, :request).new(params, request)

    result = ActionSpec::Validator::Runner.new(
      endpoint: controller.action_spec_for(:create),
      controller: runner_controller,
      coerce: true
    ).call

    expect(result.errors.details).to include(
      page: include(error: :required),
      title: include(error: :required)
    )
  end
end
