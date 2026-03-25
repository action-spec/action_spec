# frozen_string_literal: true

require "spec_helper"
require "securerandom"

RSpec.describe ActionSpec::Validator do
  include_context "with reset ActionSpec config"

  it "validates request input and exposes raw validated values on px" do
    controller = build_controller do
      before_action :validate_params!

      doc :create do
        path! :id, Integer
        query :page, Integer, default: 1
        query :request_id, String, default: -> { SecureRandom.uuid }
        header! :Authorization, String
        json data: {
          name!: String,
          birthday!: Date,
          tags: [Integer],
          profile: {
            nickname!: String
          }
        }
      end

      def create
        render json: {
          px: px.to_h,
          page_class: px[:page].class.name,
          birthday_class: px[:birthday].class.name,
          raw_page_class: params[:page].class.name,
          raw_birthday_class: params[:birthday].class.name,
          authorization: px.scope[:headers][:authorization],
          authorization_original: px.scope[:headers]["Authorization"],
          authorization_rack: px.scope[:headers]["HTTP_AUTHORIZATION"]
        }
      end
    end

    _, _, body = dispatch(
      controller,
      action: :create,
      method: "POST",
      path: "/users/7?page=2",
      params: {
        id: "7",
        name: "Tom",
        birthday: "2025-10-17",
        tags: %w[1 2],
        profile: { nickname: "neo" }
      },
      headers: { Authorization: "Bearer token" },
      route_params: { id: "7" }
    )

    payload = json_body(body)

    expect(payload.fetch("page_class")).to eq("String")
    expect(payload.fetch("birthday_class")).to eq("String")
    expect(payload.fetch("raw_page_class")).to eq("String")
    expect(payload.fetch("raw_birthday_class")).to eq("String")
    expect(payload.fetch("px")).to include("id" => "7", "page" => "2", "name" => "Tom")
    expect(payload.fetch("px").fetch("headers")).to include("authorization" => "Bearer token")
    expect(payload.fetch("authorization")).to eq("Bearer token")
    expect(payload.fetch("authorization_original")).to eq("Bearer token")
    expect(payload.fetch("authorization_rack")).to eq("Bearer token")
    expect(payload.fetch("px")).to have_key("request_id")
  end

  it "exposes built-in buckets and custom DSL scopes through px.scope" do
    controller = build_controller do
      doc :create do
        path! :account_id, Integer

        scope :user do
          query :user_id, Integer
          form data: {
            name!: String,
            admin: :boolean
          }
        end
      end

      def create; end
    end

    request = Struct.new(:path_parameters, :headers).new({ account_id: "7" }, {})
    cookies = Struct.new(:to_hash).new({})
    params = ActionController::Parameters.new(
      user_id: "9",
      name: "Tom",
      admin: "true"
    )
    runner_controller = Struct.new(:params, :request, :cookie_jar).new(params, request, cookies) do
      def send(name, *args)
        return cookie_jar if name == :cookies

        super
      end
    end

    result = ActionSpec::Validator::Runner.new(
      endpoint: controller.action_spec_for(:create),
      controller: runner_controller,
      coerce: true
    ).call

    expect(result.errors).to be_empty

    px = result.px

    expect(px.scope[:path]).to include(account_id: 7)
    expect(px.scope[:query]).to include(user_id: 9)
    expect(px.scope[:body]).to include(name: "Tom", admin: true)
    expect(px.scope[:user]).to include(user_id: 9, name: "Tom", admin: true)
  end

  it "supports compact and compact_blank on custom scopes" do
    controller = build_controller do
      doc :create do
        scope :trimmed, compact: true do
          query :page, Integer, transform: -> { nil }, px: :page_number
          query :keyword, String
        end

        scope :present_only, compact_blank: true do
          query :q, String, transform: :strip
          query :nickname, String, transform: -> { "" }
          json data: {
            tagline: { type: String, transform: -> { "" } }
          }
        end
      end

      def create; end
    end

    request = Struct.new(:path_parameters, :headers).new({}, {})
    params = ActionController::Parameters.new(
      page: "2",
      keyword: "rails",
      q: "  ruby  ",
      nickname: "Neo",
      tagline: "  "
    )
    runner_controller = Struct.new(:params, :request).new(params, request)

    result = ActionSpec::Validator::Runner.new(
      endpoint: controller.action_spec_for(:create),
      controller: runner_controller,
      coerce: true
    ).call

    expect(result.errors).to be_empty

    px = result.px

    expect(px.scope[:trimmed].to_h).to eq("keyword" => "rails")
    expect(px.scope[:present_only].to_h).to eq("q" => "ruby")
    expect(px.scope[:query]).to include(page_number: nil, keyword: "rails", q: "ruby", nickname: "")
    expect(px.scope[:body]).to include(tagline: "")
  end

  it "coerces values into px without mutating params" do
    file = Tempfile.new("action-spec")
    uploaded_file = ActionDispatch::Http::UploadedFile.new(
      tempfile: file,
      filename: "action-spec.txt",
      type: "text/plain"
    )

    controller = build_controller do
      doc :create do
        path! :id, Integer
        query :page, Integer, default: -> { 1 }
        query :enabled, :boolean, default: false
        form data: {
          file!: File,
          birthday!: Date,
          rate!: { type: Integer, range: { ge: 1, le: 5 } },
          profile: {
            nickname!: String
          }
        }
      end

      def create; end
    end

    request = Struct.new(:path_parameters, :headers).new({ id: "9" }, {})
    cookies = Struct.new(:to_hash).new({})
    params = ActionController::Parameters.new(
      birthday: "2025-10-17",
      rate: "5",
      enabled: "true",
      profile: { nickname: "neo" },
      file: uploaded_file
    )
    runner_controller = Struct.new(:params, :request, :cookie_jar).new(params, request, cookies) do
      def send(name, *args)
        return cookie_jar if name == :cookies

        super
      end
    end

    result = ActionSpec::Validator::Runner.new(
      endpoint: controller.action_spec_for(:create),
      controller: runner_controller,
      coerce: true
    ).call

    expect(result.errors).to be_empty

    px = result.px

    expect(px[:id]).to eq(9)
    expect(px[:page]).to eq(1)
    expect(px[:enabled]).to eq(true)
    expect(px[:birthday]).to eq(Date.iso8601("2025-10-17"))
    expect(px[:rate]).to eq(5)
    expect(px[:profile]).to eq("nickname" => "neo")
    expect(px[:file]).to equal(uploaded_file)
    expect(px.scope[:body]).to include(:birthday, :rate, :profile, :file)
    expect(params[:birthday]).to eq("2025-10-17")
    expect(params[:rate]).to eq("5")
    expect(params[:file]).to equal(uploaded_file)
  ensure
    file.close!
  end

  it "coerces decimal, datetime, and false boolean values" do
    controller = build_controller do
      doc :create do
        query :enabled, :boolean
        query :price, BigDecimal
        query :published_at, DateTime
      end

      def create; end
    end

    request = Struct.new(:path_parameters, :headers).new({}, {})
    params = ActionController::Parameters.new(
      enabled: "0",
      price: "12.50",
      published_at: "2025-10-17T12:30:00Z"
    )
    runner_controller = Struct.new(:params, :request).new(params, request)

    result = ActionSpec::Validator::Runner.new(
      endpoint: controller.action_spec_for(:create),
      controller: runner_controller,
      coerce: true
    ).call

    expect(result.errors).to be_empty

    px = result.px

    expect(px[:enabled]).to eq(false)
    expect(px[:price]).to eq(BigDecimal("12.5"))
    expect(px[:published_at]).to eq(DateTime.iso8601("2025-10-17T12:30:00Z"))
  end

  it "applies transform and custom px keys after coercion" do
    controller = build_controller do
      doc :create do
        query :page, Integer, transform: ->(value) { value + 1 }, px: :page_number
        query :slug, String, transform: :upcase, px_key: :slug_value
        header :X_Request_Id, String, px_key: :request_id

        scope :search do
          query :term, String, transform: :strip, px: :keyword
        end

        json data: {
          profile!: {
            nickname: { type: String, transform: ->(value) { value.strip.downcase }, px_key: :handle }
          }
        }
      end

      def create; end
    end

    request = Struct.new(:path_parameters, :headers).new({}, { "X-Request-Id" => "req-1" })
    params = ActionController::Parameters.new(
      page: "2",
      slug: "neo",
      term: "  ruby  ",
      profile: { nickname: "  Neo  " }
    )
    runner_controller = Struct.new(:params, :request).new(params, request)

    result = ActionSpec::Validator::Runner.new(
      endpoint: controller.action_spec_for(:create),
      controller: runner_controller,
      coerce: true
    ).call

    expect(result.errors).to be_empty

    px = result.px

    expect(px[:page_number]).to eq(3)
    expect(px[:slug_value]).to eq("NEO")
    expect(px).not_to have_key("page")
    expect(px).not_to have_key("slug")
    expect(px[:profile]).to eq("handle" => "neo")
    expect(px.scope[:query]).to include(page_number: 3, slug_value: "NEO", keyword: "ruby")
    expect(px.scope[:headers]).to include(request_id: "req-1")
    expect(px.scope[:search]).to include(keyword: "ruby")
  end
end
