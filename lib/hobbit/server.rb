require 'rack'

module Hobbit
  attr_accessor :app
  attr_accessor :server_socket
  class Server
    include Util

    def initialize(app, options = {})
      @app = app # Rack
      @config = Config.new(options)

      # Socket Pair for pass client socket to worker process
      @fd_send, @fd_recv = UNIXSocket.pair

      @worker_pids = []

      @config.worker_number.times do
        spawn_worker
      end

      @server_socket = TCPServer.new(@config.host, @config.port)
      puts_my_pid_with("Start Hobbit Server... #{@config.host}:#{@config.port}")

      trap(:SIGINT) do
        @worker_pids.each do |pid|
          puts_my_pid_with("Worker exit...")
          Process.kill(:SIGINT, pid)
          Process.waitpid(pid)
        end
        exit(0)
      end

      run
    end

    def run
      # handle request one by one
      loop do
        # get request
        client_socket = @server_socket.accept
        enqueue_client(client_socket)
      end
      @server_socket.close
    end

    # for enqueue client socket at master process
    def enqueue_client(client_socket)
      @fd_send.send_io client_socket
    end

    def spawn_worker
      @worker_pids << fork do
        Worker.new(@app, @fd_recv).wait_request
      end
    end
  end
end
