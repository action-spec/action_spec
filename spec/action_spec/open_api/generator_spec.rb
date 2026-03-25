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
    expect(operation.fetch("operationId")).to eq("users_create")
    expect(operation.fetch("tags")).to eq(["users"])
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

  it "marks request bodies as required for json! and required: true declarations" do
    stub_const("ProfilesController", Class.new(ActionController::Base) do
      include ActionSpec::Doc

      doc(:create, "Create profile") do
        json data: { nickname: { type: String, required: true } }, required: true
      end

      def create; end
    end)

    document = described_class.new(
      routes: [
        Route.new(
          verb: "POST",
          path: "/profiles",
          defaults: { controller: "profiles", action: "create" }
        )
      ],
      title: "ActionSpec Demo",
      version: "2026.03"
    ).call

    operation = document.dig("paths", "/profiles", "post")
    request_body = operation.fetch("requestBody")

    expect(request_body.fetch("required")).to eq(true)
    expect(request_body.dig("content", "application/json", "schema")).to include(
      "required" => include("nickname")
    )
  end

  it "treats type: Hash the same as type: Object in generated object schemas" do
    stub_const("SettingsController", Class.new(ActionController::Base) do
      include ActionSpec::Doc

      doc(:create, "Create settings") do
        json data: {
          settings: {
            type: Hash,
            theme!: String
          }
        }
      end

      def create; end
    end)

    document = described_class.new(
      routes: [
        Route.new(
          verb: "POST",
          path: "/settings",
          defaults: { controller: "settings", action: "create" }
        )
      ],
      title: "ActionSpec Demo",
      version: "2026.03"
    ).call

    schema = document.dig("paths", "/settings", "post", "requestBody", "content", "application/json", "schema")

    expect(schema).to include(
      "properties" => include(
        "settings" => include(
          "type" => "object",
          "required" => include("theme"),
          "properties" => include("theme" => include("type" => "string"))
        )
      )
    )
  end

  it "emits object defaults for schemas declared through type: { ... }" do
    stub_const("UsersController", Class.new(ActionController::Base) do
      include ActionSpec::Doc

      doc(:create, "Create users") do
        json data: {
          users: {
            type: { name!: String },
            default: { name: "Tom" }
          }
        }
      end

      def create; end
    end)

    document = described_class.new(
      routes: [
        Route.new(
          verb: "POST",
          path: "/users",
          defaults: { controller: "users", action: "create" }
        )
      ],
      title: "ActionSpec Demo",
      version: "2026.03"
    ).call

    schema = document.dig("paths", "/users", "post", "requestBody", "content", "application/json", "schema")

    expect(schema).to include(
      "properties" => include(
        "users" => include(
          "type" => "object",
          "default" => { "name" => "Tom" },
          "required" => include("name"),
          "properties" => include("name" => include("type" => "string"))
        )
      )
    )
  end

  it "treats type: [] the same as [] in generated array schemas" do
    stub_const("TagsController", Class.new(ActionController::Base) do
      include ActionSpec::Doc

      doc(:create, "Create tags") do
        json data: {
          tags: { type: [] }
        }
      end

      def create; end
    end)

    document = described_class.new(
      routes: [
        Route.new(
          verb: "POST",
          path: "/tags",
          defaults: { controller: "tags", action: "create" }
        )
      ],
      title: "ActionSpec Demo",
      version: "2026.03"
    ).call

    schema = document.dig("paths", "/tags", "post", "requestBody", "content", "application/json", "schema")

    expect(schema).to include(
      "properties" => include(
        "tags" => include(
          "type" => "array",
          "items" => include("type" => "string")
        )
      )
    )
  end

  it "emits error response schemas from schema hashes and defaults the media type to json" do
    stub_const("PaymentsController", Class.new(ActionController::Base) do
      include ActionSpec::Doc

      doc(:create, "Create payment") do
        error 503, { code!: Integer, message!: String }
      end

      def create; end
    end)

    document = described_class.new(
      routes: [
        Route.new(
          verb: "POST",
          path: "/payments",
          defaults: { controller: "payments", action: "create" }
        )
      ],
      title: "ActionSpec Demo",
      version: "2026.03"
    ).call

    response = document.dig("paths", "/payments", "post", "responses", "503")

    expect(response.fetch("description")).to eq("Error")
    expect(response.dig("content", "application/json", "schema")).to include(
      "type" => "object",
      "required" => contain_exactly("code", "message"),
      "properties" => include(
        "code" => include("type" => "integer"),
        "message" => include("type" => "string")
      )
    )
  end

  it "treats the second positional argument as media type when it is a known response media type" do
    stub_const("SessionsController", Class.new(ActionController::Base) do
      include ActionSpec::Doc

      doc(:create, "Create session") do
        response 422, :json, data: { code!: Integer, message!: String }
      end

      def create; end
    end)

    document = described_class.new(
      routes: [
        Route.new(
          verb: "POST",
          path: "/sessions",
          defaults: { controller: "sessions", action: "create" }
        )
      ],
      title: "ActionSpec Demo",
      version: "2026.03"
    ).call

    response = document.dig("paths", "/sessions", "post", "responses", "422")

    expect(response.fetch("description")).to eq("OK")
    expect(response.dig("content", "application/json", "schema")).to include(
      "required" => contain_exactly("code", "message"),
      "properties" => include(
        "code" => include("type" => "integer"),
        "message" => include("type" => "string")
      )
    )
  end

  it "treats bare error hashes as unnamed examples and infers the response schema" do
    stub_const("ImportsController", Class.new(ActionController::Base) do
      include ActionSpec::Doc

      doc(:create, "Create import") do
        error 503, { code: 1000, message: "network error" }
      end

      def create; end
    end)

    document = described_class.new(
      routes: [
        Route.new(
          verb: "POST",
          path: "/imports",
          defaults: { controller: "imports", action: "create" }
        )
      ],
      title: "ActionSpec Demo",
      version: "2026.03"
    ).call

    response = document.dig("paths", "/imports", "post", "responses", "503")

    expect(response.dig("content", "application/json", "schema")).to include(
      "required" => contain_exactly("code", "message"),
      "properties" => include(
        "code" => include("type" => "integer"),
        "message" => include("type" => "string")
      )
    )
    expect(response.dig("content", "application/json", "example")).to eq(
      "code" => 1000,
      "message" => "network error"
    )
  end

  it "supports named error examples and the errors batch helper" do
    stub_const("ExportsController", Class.new(ActionController::Base) do
      include ActionSpec::Doc

      doc(:create, "Create export") do
        error 503, invalid_params: { code: 1000, message: "invalid params" }
        errors 503,
          network_error: { code: 1001, message: "network error" },
          upstream_timeout: { code: 1002, message: "upstream timeout" }
      end

      def create; end
    end)

    document = described_class.new(
      routes: [
        Route.new(
          verb: "POST",
          path: "/exports",
          defaults: { controller: "exports", action: "create" }
        )
      ],
      title: "ActionSpec Demo",
      version: "2026.03"
    ).call

    response = document.dig("paths", "/exports", "post", "responses", "503")
    content = response.dig("content", "application/json")

    expect(content.dig("schema", "required")).to contain_exactly("code", "message")
    expect(content.fetch("examples")).to eq(
      "invalid_params" => { "value" => { "code" => 1000, "message" => "invalid params" } },
      "network_error" => { "value" => { "code" => 1001, "message" => "network error" } },
      "upstream_timeout" => { "value" => { "code" => 1002, "message" => "upstream timeout" } }
    )
  end

  it "also supports the braced errors hash form" do
    stub_const("JobsController", Class.new(ActionController::Base) do
      include ActionSpec::Doc

      doc(:create, "Create job") do
        errors 503, {
          invalid_params: { code: 1000, message: "invalid params" },
          network_error: { code: 1001, message: "network error" }
        }
      end

      def create; end
    end)

    document = described_class.new(
      routes: [
        Route.new(
          verb: "POST",
          path: "/jobs",
          defaults: { controller: "jobs", action: "create" }
        )
      ],
      title: "ActionSpec Demo",
      version: "2026.03"
    ).call

    response = document.dig("paths", "/jobs", "post", "responses", "503")

    expect(response.dig("content", "application/json", "examples")).to eq(
      "invalid_params" => { "value" => { "code" => 1000, "message" => "invalid params" } },
      "network_error" => { "value" => { "code" => 1001, "message" => "network error" } }
    )
  end

  it "uses doc(tag:) to override the default controller_path tag" do
    stub_const("AuctionsController", Class.new(ActionController::Base) do
      include ActionSpec::Doc

      doc(:index, "List auctions", tag: "marketplace") do
        query :status, String
      end

      def index; end
    end)

    document = described_class.new(
      routes: [
        Route.new(
          verb: "GET",
          path: "/auctions",
          defaults: { controller: "auctions", action: "index" }
        )
      ],
      title: "ActionSpec Demo",
      version: "2026.03"
    ).call

    operation = document.dig("paths", "/auctions", "get")

    expect(operation.fetch("operationId")).to eq("marketplace_index")
    expect(operation.fetch("tags")).to eq(["marketplace"])
  end

  it "uses doc_dry(tag:) to set tags for matching actions" do
    stub_const("Admin::OrdersController", Class.new(ActionController::Base) do
      include ActionSpec::Doc

      doc_dry :index, tag: "backoffice"

      doc(:index, "List orders") do
        query :status, String
      end

      def index; end
    end)

    document = described_class.new(
      routes: [
        Route.new(
          verb: "GET",
          path: "/admin/orders",
          defaults: { controller: "admin/orders", action: "index" }
        )
      ],
      title: "ActionSpec Demo",
      version: "2026.03"
    ).call

    operation = document.dig("paths", "/admin/orders", "get")

    expect(operation.fetch("operationId")).to eq("backoffice_index")
    expect(operation.fetch("tags")).to eq(["backoffice"])
  end

  it "lets doc(tag:) override a tag inherited from doc_dry(tag:)" do
    stub_const("Admin::UsersController", Class.new(ActionController::Base) do
      include ActionSpec::Doc

      doc_dry :index, tag: "backoffice"

      doc(:index, "List users", tag: "members") do
        query :status, String
      end

      def index; end
    end)

    document = described_class.new(
      routes: [
        Route.new(
          verb: "GET",
          path: "/admin/users",
          defaults: { controller: "admin/users", action: "index" }
        )
      ],
      title: "ActionSpec Demo",
      version: "2026.03"
    ).call

    operation = document.dig("paths", "/admin/users", "get")

    expect(operation.fetch("operationId")).to eq("members_index")
    expect(operation.fetch("tags")).to eq(["members"])
  end

  it "skips endpoints marked with openapi false inside doc" do
    stub_const("InternalUsersController", Class.new(ActionController::Base) do
      include ActionSpec::Doc

      doc(:index, "Internal users") do
        openapi false
        query :page, Integer
      end

      def index; end
    end)

    document = described_class.new(
      routes: [
        Route.new(
          verb: "GET",
          path: "/internal/users",
          defaults: { controller: "internal_users", action: "index" }
        )
      ],
      title: "ActionSpec Demo",
      version: "2026.03"
    ).call

    expect(document.fetch("paths")).to eq({})
  end

  it "skips endpoints marked with openapi false inside doc_dry" do
    stub_const("AdminReportsController", Class.new(ActionController::Base) do
      include ActionSpec::Doc

      doc_dry :index do
        openapi false
      end

      doc(:index, "Admin reports") do
        query :page, Integer
      end

      def index; end
    end)

    document = described_class.new(
      routes: [
        Route.new(
          verb: "GET",
          path: "/admin/reports",
          defaults: { controller: "admin_reports", action: "index" }
        )
      ],
      title: "ActionSpec Demo",
      version: "2026.03"
    ).call

    expect(document.fetch("paths")).to eq({})
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
      yaml = File.read(output)

      expect(yaml).not_to include("!omap")
      expect(yaml).to include("/profiles/{id}:")
      expect(yaml).not_to include("\"/profiles/{id}\":")
      content = YAML.safe_load_file(output)

      expect(content.dig("paths", "/profiles/{id}", "get", "summary")).to eq("Show profile")
    end
  end

  it "omits defaults and examples that are not JSON-compatible OpenAPI values" do
    stub_const("MetricsController", Class.new(ActionController::Base) do
      include ActionSpec::Doc

      doc(:create, "Create metric") do
        query :ratio, BigDecimal, default: BigDecimal("0.6"), example: BigDecimal("0.7"), examples: [BigDecimal("0.8")]
      end

      def create; end
    end)

    Dir.mktmpdir do |dir|
      output = File.join(dir, "openapi.yml")

      described_class.generate!(
        routes: [
          Route.new(
            verb: "POST",
            path: "/metrics",
            defaults: { controller: "metrics", action: "create" }
          )
        ],
        title: "ActionSpec Demo",
        version: "2026.03",
        output:
      )

      content = File.read(output)
      document = YAML.safe_load_file(output)
      ratio_schema = document.dig("paths", "/metrics", "post", "parameters", 0, "schema")

      expect(content).not_to include("!ruby/object:BigDecimal")
      expect(content).not_to match(/\n\s+default:\s*\n/)
      expect(content).not_to match(/\n\s+example:\s*\n/)
      expect(content).not_to match(/\n\s+examples:\s*\n/)
      expect(ratio_schema).to include("type" => "number", "format" => "double")
      expect(ratio_schema.keys).not_to include("default", "example", "examples")
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

  it "resolves namespaced controllers from routed controller names" do
    module Admin
      class UsersController < ActionController::Base
        include ActionSpec::Doc

        doc(:index, "List admin users") { }

        def index; end
      end
    end

    document = described_class.new(
      routes: [
        Route.new(
          verb: "GET",
          path: "/admin/users",
          defaults: { controller: "admin/users", action: "index" }
        )
      ],
      title: "ActionSpec Demo",
      version: "2026.03"
    ).call

    expect(document.dig("paths", "/admin/users", "get", "summary")).to eq("List admin users")
  end

  it "emits every routed HTTP verb instead of keeping only the first one" do
    stub_const("ProfilesController", Class.new(ActionController::Base) do
      include ActionSpec::Doc

      doc(:replace, "Replace profile") { }
      doc(:update, "Update profile") { }

      def replace; end
      def update; end
    end)

    document = described_class.new(
      routes: [
        Route.new(
          verb: "PATCH|PUT",
          path: "/profiles/:id",
          defaults: { controller: "profiles", action: "update" }
        )
      ],
      title: "ActionSpec Demo",
      version: "2026.03"
    ).call

    expect(document.dig("paths", "/profiles/{id}", "patch", "summary")).to eq("Update profile")
    expect(document.dig("paths", "/profiles/{id}", "put", "summary")).to eq("Update profile")
  end
end
