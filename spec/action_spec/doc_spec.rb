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

  it "tracks custom scope options declared on scope blocks" do
    controller = build_controller do
      doc :create do
        scope :user, compact: true do
          query :user_id, Integer
        end

        scope :profile, compact_blank: true do
          query :nickname, String
        end
      end

      def create; end
    end

    endpoint = controller.action_spec_for(:create)

    expect(endpoint.request.scope_options[:user].symbolize_keys).to eq(compact: true)
    expect(endpoint.request.scope_options[:profile].symbolize_keys).to eq(compact_blank: true)
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

  it "supports object schemas declared through type: { ... } with object defaults" do
    controller = build_controller do
      doc :create do
        json data: {
          users: {
            type: { name!: String },
            default: { name: "Tom" }
          }
        }
      end

      def create; end
    end

    field = controller.action_spec_for(:create).request.body.field(:users)

    expect(field.schema).to be_a(ActionSpec::Schema::ObjectOf)
    expect(field.schema.default).to eq(name: "Tom")
    expect(field.schema.fields.keys).to eq([:name])
    expect(field.schema.fields.fetch(:name)).to be_required
  end

  it "tracks whether a request tree contains custom validate callbacks" do
    controller = build_controller do
      doc :create do
        query :page, Integer
        json data: {
          user: {
            type: {
              name: { type: String, validate: -> { it.present? } }
            }
          }
        }
      end

      def create; end
    end

    request = controller.action_spec_for(:create).request

    expect(request).to be_custom_validation
    expect(request.query).not_to be_custom_validation
    expect(request.body).to be_custom_validation
    expect(request.body.field(:user)).to be_custom_validation
  end

  it "updates cached custom validation lookups when fields are added later" do
    request = ActionSpec::Doc::Request.new

    expect(request).not_to be_custom_validation
    expect(request.query).not_to be_custom_validation

    request.add_param(
      :query,
      ActionSpec::Schema.build_field(
        :filters,
        {
          type: {
          keyword: { type: String, validate: -> { it.present? } }
          }
        }
      )
    )

    expect(request).to be_custom_validation
    expect(request.custom_validation_locations.map(&:name)).to eq([:query])
    expect(request.query).to be_custom_validation
    expect(request.query.custom_validation_fields.map(&:name)).to eq([:filters])
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

  it "accepts openapi: false as a doc option" do
    controller = build_controller do
      doc :create, openapi: false do
        query :page, Integer
      end

      def create; end
    end

    expect(controller.action_spec_for(:create).options[:openapi]).to eq(false)
  end

  it "accepts openapi: true as a doc option and lets it override dry options" do
    base_controller = build_controller do
      doc_dry :index, openapi: false
    end

    controller = Class.new(base_controller) do
      doc :index, openapi: true do
        query :page, Integer
      end

      def index; end
    end

    expect(controller.action_spec_for(:index).options[:openapi]).to eq(true)
  end
end
