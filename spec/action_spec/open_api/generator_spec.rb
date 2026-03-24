# frozen_string_literal: true

require "spec_helper"

RSpec.describe ActionSpec::OpenApi::Generator do
  include_context "with reset ActionSpec config"

  Route = Struct.new(:verb, :path, :defaults, keyword_init: true)

  it "builds an OpenAPI 3.2 document from controller docs and routes" do
    stub_const("UsersController", Class.new(ActionController::Base) do
      include ActionSpec::Doc

      doc(:create, "Create user") do
        path! :account_id, Integer, desc: "Account id"
        query :page, Integer, default: 1
        query :request_id, String, default: -> { SecureRandom.uuid }
        header! :Authorization, String
        cookie :remember_token, String

        json data: {
          name!: String,
          age: { type: Integer, range: { ge: 18, le: 80 } },
          admin: { type: :boolean, default: false },
          tags: [String],
          profile: {
            nickname!: String
          }
        }

        response 201, "created"
        error 422, "validation failed"
      end

      def create; end
    end)

    document = described_class.new(
      routes: [
        Route.new(
          verb: "POST",
          path: "/accounts/:account_id/users(.:format)",
          defaults: { controller: "users", action: "create" }
        )
      ],
      title: "ActionSpec Demo",
      version: "2026.03"
    ).call

    expect(document.fetch("openapi")).to eq("3.2.0")
    expect(document.fetch("info")).to eq(
      "title" => "ActionSpec Demo",
      "version" => "2026.03"
    )

    operation = document.dig("paths", "/accounts/{account_id}/users", "post")

    expect(operation.fetch("summary")).to eq("Create user")
    expect(operation.fetch("parameters")).to include(
      include(
        "name" => "account_id",
        "in" => "path",
        "required" => true,
        "description" => "Account id",
        "schema" => include("type" => "integer")
      ),
      include(
        "name" => "page",
        "in" => "query",
        "required" => false,
        "schema" => include("type" => "integer", "default" => 1)
      ),
      include(
        "name" => "Authorization",
        "in" => "header",
        "required" => true,
        "schema" => include("type" => "string")
      ),
      include(
        "name" => "remember_token",
        "in" => "cookie",
        "required" => false,
        "schema" => include("type" => "string")
      )
    )

    request_body = operation.fetch("requestBody")
    json_schema = request_body.dig("content", "application/json", "schema")

    expect(request_body.keys).not_to include("required")
    expect(json_schema).to include(
      "type" => "object",
      "required" => include("name"),
      "properties" => include(
        "name" => include("type" => "string"),
        "age" => include("type" => "integer", "minimum" => 18, "maximum" => 80),
        "admin" => include("type" => "boolean", "default" => false),
        "tags" => include("type" => "array", "items" => include("type" => "string")),
        "profile" => include(
          "type" => "object",
          "required" => include("nickname"),
          "properties" => include("nickname" => include("type" => "string"))
        )
      )
    )
    expect(operation.fetch("responses")).to eq(
      "201" => { "description" => "created" },
      "422" => { "description" => "validation failed" }
    )
  end

  it "maps multipart file fields and falls back to a default success response" do
    stub_const("UploadsController", Class.new(ActionController::Base) do
      include ActionSpec::Doc

      doc(:create, "Upload file") do
        form data: { file!: File, position: String }
      end

      def create; end
    end)

    document = described_class.new(
      routes: [
        Route.new(
          verb: "POST",
          path: "/uploads",
          defaults: { controller: "uploads", action: "create" }
        )
      ],
      title: "ActionSpec Demo",
      version: "2026.03"
    ).call

    operation = document.dig("paths", "/uploads", "post")
    schema = operation.dig("requestBody", "content", "multipart/form-data", "schema")

    expect(schema).to include(
      "type" => "object",
      "required" => include("file"),
      "properties" => include(
        "file" => include("type" => "string", "format" => "binary"),
        "position" => include("type" => "string")
      )
    )
    expect(operation.fetch("responses")).to eq("200" => { "description" => "OK" })
  end

  it "writes YAML output when asked" do
    stub_const("ProfilesController", Class.new(ActionController::Base) do
      include ActionSpec::Doc

      doc(:show, "Show profile") do
        path! :id, Integer
      end

      def show; end
    end)

    Dir.mktmpdir do |dir|
      output = File.join(dir, "openapi.yml")

      described_class.generate!(
        routes: [
          Route.new(
            verb: "GET",
            path: "/profiles/:id",
            defaults: { controller: "profiles", action: "show" }
          )
        ],
        title: "ActionSpec Demo",
        version: "2026.03",
        output:
      )

      expect(File).to exist(output)
      content = YAML.safe_load_file(output)

      expect(content.dig("paths", "/profiles/{id}", "get", "summary")).to eq("Show profile")
    end
  end

  it "falls back to application-derived info when title and version are not provided" do
    module DemoApi
      class Application; end
    end

    stub_const("StatusController", Class.new(ActionController::Base) do
      include ActionSpec::Doc

      doc(:show, "Status") { }

      def show; end
    end)

    application = instance_double("Rails::Application")
    allow(application).to receive(:class).and_return(DemoApi::Application)

    document = described_class.new(
      application:,
      routes: [
        Route.new(
          verb: "GET",
          path: "/status",
          defaults: { controller: "status", action: "show" }
        )
      ]
    ).call

    expect(document.fetch("info")).to eq(
      "title" => "Demo Api",
      "version" => "1.0.0"
    )
  end
end
