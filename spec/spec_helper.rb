# frozen_string_literal: true

require "json"
require "rack/mock"
require "tempfile"
require "tmpdir"
require "active_support"
require "active_support/core_ext"
require "action_controller/railtie"
require "action_dispatch"

require_relative "../lib/action_spec"

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
  end
end

module SpecSupport
  def build_controller(&block)
    Class.new(ActionController::Base) do
      include ActionSpec::Doc
      include ActionSpec::Validator
      include ActionController::StrongParameters

      define_singleton_method(:name) { "SpecController#{object_id}" }

      class_eval(&block)
    end
  end

  def build_controller_from_source(source)
    file = Tempfile.new([ "action-spec-controller", ".rb" ])
    file.write(source)
    file.flush

    Class.new(ActionController::Base) do
      include ActionSpec::Doc
      include ActionSpec::Validator
      include ActionController::StrongParameters

      define_singleton_method(:name) { "SpecController#{object_id}" }

      class_eval(File.read(file.path), file.path, 1)
    end
  ensure
    file&.close
  end

  def dispatch(controller_class, action:, method:, path:, params: nil, headers: {}, cookies: {}, route_params: {})
    env = Rack::MockRequest.env_for(path, method:, params:)
    headers.each do |key, value|
      env[header_name(key)] = value
      env[key.to_s] = value
    end

    cookie_header = cookies.map { |key, value| "#{key}=#{value}" }.join("; ")
    env["HTTP_COOKIE"] = cookie_header if cookie_header.present?
    env["action_dispatch.request.path_parameters"] = {
      controller: controller_class.controller_path,
      action: action.to_s
    }.merge(route_params.stringify_keys)

    status, response_headers, body = controller_class.action(action).call(env)
    [status, response_headers, body.each.to_a.join]
  end

  def json_body(body)
    JSON.parse(body)
  end

  private

    def header_name(key)
      normalized = key.to_s.upcase.tr("-", "_")
      normalized.start_with?("HTTP_") ? normalized : "HTTP_#{normalized}"
    end
end

RSpec.configure do |config|
  config.include SpecSupport
end

RSpec.shared_context "with reset ActionSpec config" do
  around do |example|
    previous = ActionSpec.config.dup
    example.run
  ensure
    ActionSpec.instance_variable_set(:@config, previous)
  end
end
