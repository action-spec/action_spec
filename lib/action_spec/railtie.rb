module ActionSpec
  class Railtie < ::Rails::Railtie
    initializer "action_spec.i18n" do |app|
      app.config.i18n.load_path += Dir[root.join("config/locales/*.yml")]
    end

    initializer "action_spec.controller" do
      ActiveSupport.on_load(:action_controller_base) do
        include ActionSpec::Doc
        include ActionSpec::Validator
      end
    end
  end
end
