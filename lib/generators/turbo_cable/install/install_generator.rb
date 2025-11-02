module TurboCable
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      def copy_javascript_controller
        copy_file "turbo_streams_controller.js",
          "app/javascript/controllers/turbo_streams_controller.js"
      end

      def add_controller_to_layout
        layout_file = "app/views/layouts/application.html.erb"

        if File.exist?(layout_file)
          # Check if already added
          content = File.read(layout_file)
          unless content.include?('data-controller="turbo-streams"')
            inject_into_file layout_file,
              ' data-controller="turbo-streams"',
              after: '<body'
          end
        else
          say "WARNING: Could not find #{layout_file}", :yellow
          say "Please add data-controller=\"turbo-streams\" to your <body> tag manually", :yellow
        end
      end

      def show_readme
        say "\n" + "=" * 70
        say "TurboCable Installation Complete!", :green
        say "=" * 70
        say "\nNext steps:"
        say "  1. Restart your Rails server"
        say "  2. Use turbo_stream_from in your views"
        say "  3. Use broadcast_* methods in your models"
        say "\nExample usage:"
        say "  # In your view"
        say '  <%= turbo_stream_from "counter_updates" %>'
        say "\n  # In your model"
        say '  broadcast_replace_later_to "counter_updates", target: "counter"'
        say "\nFor more information, see the README at:"
        say "  https://github.com/rubys/turbo_cable"
        say "\n" + "=" * 70 + "\n"
      end
    end
  end
end
