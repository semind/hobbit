module Hobbit
  class Config
    attr_accessor :host, :port, :worker_number

    def initialize(options = {})
      @host = options[:Host] || '127.0.0.1'
      @port = options[:Port] || 1981
      @worker_number = options[:worker_number] || 2
    end
  end
end
