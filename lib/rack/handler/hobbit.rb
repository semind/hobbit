require 'rack/handler'
require 'hobbit'

module Rack
  module Handler
    module Hobbit
      def self.run(app, options = {})
        server = ::Hobbit::Server.new(app, options)
      end
    end

    register :hobbit, Hobbit
  end
end
