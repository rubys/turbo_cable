module TurboCable
  class Engine < ::Rails::Engine
    isolate_namespace TurboCable

    # Add Rack middleware for WebSocket handling
    initializer "turbo_cable.middleware" do |app|
      app.middleware.use TurboCable::RackHandler
    end

    # Prepend Broadcastable in ApplicationRecord (overrides turbo-rails methods)
    initializer "turbo_cable.active_record" do
      ActiveSupport.on_load(:active_record) do
        prepend TurboCable::Broadcastable
      end
    end

    # Make helpers available to the host application
    initializer "turbo_cable.helpers" do
      ActiveSupport.on_load(:action_controller_base) do
        helper TurboCable::StreamsHelper
      end
    end
  end
end
