namespace :action_spec do
  desc "Generate an OpenAPI 3.2 document from ActionSpec controller docs"
  task gen: :environment do
    config = ActionSpec.config

    ActionSpec::OpenApi::Generator.generate!(
      application: Rails.application,
      output: Rails.root.join(ENV.fetch("OUTPUT", config.open_api_output)).to_s,
      title: ENV["TITLE"].presence || config.open_api_title,
      version: ENV["VERSION"].presence || config.open_api_version,
      server_url: ENV["SERVER_URL"].presence || config.open_api_server_url
    )
  end
end
