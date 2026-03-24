# frozen_string_literal: true

require "spec_helper"
require "rake"

RSpec.describe "action_spec:gen task" do
  include_context "with reset ActionSpec config"

  around do |example|
    original_rake = Rake.application
    original_env = ENV.to_h
    Rake.application = Rake::Application.new
    Rake.application.define_task(Rake::Task, :environment)
    example.run
  ensure
    ENV.replace(original_env)
    Rake.application = original_rake
  end

  it "delegates to the OpenAPI generator with the default output path" do
    load File.expand_path("../../../lib/tasks/action_spec_tasks.rake", __dir__)

    application = instance_double("Rails::Application")
    root = Pathname.new("/tmp/action-spec-app")

    allow(Rails).to receive(:application).and_return(application)
    allow(Rails).to receive(:root).and_return(root)
    allow(ActionSpec::OpenApi::Generator).to receive(:generate!)

    Rake::Task["action_spec:gen"].invoke

    expect(ActionSpec::OpenApi::Generator).to have_received(:generate!).with(
      application:,
      output: root.join("docs", "openapi.yml").to_s,
      title: nil,
      version: nil,
      server_url: nil
    )
  end

  it "uses ActionSpec configuration values when present" do
    load File.expand_path("../../../lib/tasks/action_spec_tasks.rake", __dir__)

    application = instance_double("Rails::Application")
    root = Pathname.new("/tmp/action-spec-app")

    ActionSpec.configure do |config|
      config.open_api_output = "docs/public-openapi.yml"
      config.open_api_title = "Configured API"
      config.open_api_version = "2026.03"
      config.open_api_server_url = "https://configured.example.com"
    end

    allow(Rails).to receive(:application).and_return(application)
    allow(Rails).to receive(:root).and_return(root)
    allow(ActionSpec::OpenApi::Generator).to receive(:generate!)

    Rake::Task["action_spec:gen"].invoke

    expect(ActionSpec::OpenApi::Generator).to have_received(:generate!).with(
      application:,
      output: root.join("docs", "public-openapi.yml").to_s,
      title: "Configured API",
      version: "2026.03",
      server_url: "https://configured.example.com"
    )
  end

  it "lets environment variables override ActionSpec configuration" do
    load File.expand_path("../../../lib/tasks/action_spec_tasks.rake", __dir__)

    application = instance_double("Rails::Application")
    root = Pathname.new("/tmp/action-spec-app")

    ActionSpec.configure do |config|
      config.open_api_output = "docs/public-openapi.yml"
      config.open_api_title = "Configured API"
      config.open_api_version = "2026.03"
      config.open_api_server_url = "https://configured.example.com"
    end

    ENV["OUTPUT"] = "docs/env-openapi.yml"
    ENV["TITLE"] = "Env API"
    ENV["VERSION"] = "2027.01"
    ENV["SERVER_URL"] = "https://env.example.com"

    allow(Rails).to receive(:application).and_return(application)
    allow(Rails).to receive(:root).and_return(root)
    allow(ActionSpec::OpenApi::Generator).to receive(:generate!)

    Rake::Task["action_spec:gen"].invoke

    expect(ActionSpec::OpenApi::Generator).to have_received(:generate!).with(
      application:,
      output: root.join("docs", "env-openapi.yml").to_s,
      title: "Env API",
      version: "2027.01",
      server_url: "https://env.example.com"
    )
  end
end
