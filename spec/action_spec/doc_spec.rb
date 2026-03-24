# frozen_string_literal: true

require "spec_helper"

RSpec.describe ActionSpec::Doc do
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
end
