module ActionSpec
  class Railtie < ::Rails::Railtie
    rake_tasks do
      load File.expand_path("../tasks/action_spec_tasks.rake", __dir__)
    end

    initializer "action_spec.controller" do
      ActiveSupport.on_load(:action_controller_base) do
        include ActionSpec::Doc
        include ActionSpec::Validator
      end
    end

    initializer "action_spec.active_record" do
      ActiveSupport.on_load(:active_record) do
        include ActionSpec::Schema::ActiveRecord
      end
    end
  end
end
