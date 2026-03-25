# frozen_string_literal: true

require "spec_helper"

RSpec.describe ActionSpec::Doc do
  include_context "with reset ActionSpec config"

  it "supports explicit action binding with doc :action" do
    base_controller = build_controller do
      doc_dry %i[show update destroy] do
        path! :id, Integer
      end
    end

    controller = Class.new(base_controller) do
      define_singleton_method(:name) { "PeopleController" }

      doc :show, "Show person" do
        query :locale, String, default: "zh-CN"
        response 200, desc: "success"
      end
      def show; end
    end

    endpoint = controller.action_spec_for(:show)

    expect(endpoint.summary).to eq("Show person")
    expect(endpoint.request.path.field(:id)).to be_required
    expect(endpoint.request.query.field(:locale).default_value).to eq("zh-CN")
    expect(endpoint.responses.fetch("200").description).to eq("success")
  end

  it "infers the next action for the existing doc { } style without method hooks" do
    controller = build_controller_from_source <<~RUBY
      doc("Index users")
      def index; end
    RUBY

    endpoint = controller.action_spec_for(:index)

    expect(endpoint.summary).to eq("Index users")
    expect(endpoint.request.query.fields).to be_empty
  end

  it "tracks custom scopes for fields declared inside scope blocks" do
    controller = build_controller do
      doc :create do
        scope :user do
          query :user_id, Integer
          form data: { name!: String }
        end
      end

      def create; end
    end

    endpoint = controller.action_spec_for(:create)

    expect(endpoint.request.query.field(:user_id).scopes).to eq([:user])
    expect(endpoint.request.body.field(:name).scopes).to eq([:user])
  end

  it "supports required: true without bang syntax for params, nested fields, and body" do
    controller = build_controller do
      doc :create do
        query :page, Integer, required: true
        json data: {
          title: { type: String, required: true }
        }, required: true
      end

      def create; end
    end

    endpoint = controller.action_spec_for(:create)

    expect(endpoint.request.query.field(:page)).to be_required
    expect(endpoint.request.body.field(:title)).to be_required
    expect(endpoint.request).to be_body_required
  end

  it "does not expose the removed resp alias" do
    controller = build_controller do
      doc :create do
        response 200, "ok"
      end

      def create; end
    end

    expect(controller.action_spec_for(:create).dsl).not_to respond_to(:resp)
  end

  it "defaults response and error declarations to json media type" do
    controller = build_controller do
      doc :create do
        response 200, "ok"
        error 503, { code!: Integer, message!: String }
      end

      def create; end
    end

    endpoint = controller.action_spec_for(:create)

    expect(endpoint.responses.fetch("200").media_types.keys).to eq([:json])
    expect(endpoint.responses.fetch("503").media_types.keys).to eq([:json])
  end

  it "lets configuration override the default response media type" do
    ActionSpec.configure do |config|
      config.default_response_media_type = :form
    end

    controller = build_controller do
      doc :create do
        response 200, "ok"
        error 503, { code!: Integer, message!: String }
      end

      def create; end
    end

    endpoint = controller.action_spec_for(:create)

    expect(endpoint.responses.fetch("200").media_types.keys).to eq([:form])
    expect(endpoint.responses.fetch("503").media_types.keys).to eq([:form])
  end
end
