require 'rack'

module Hobbit
  attr_accessor :app
  attr_accessor :server_socket
  class Server
    include Util

    def initialize(app, options = {})
      @app = app # Rack

      # Socket Pair for pass client socket to worker process
      @fd_send, @fd_recv = UNIXSocket.pair

      @worker_pids = []

      spawn_worker

      host = options[:host] || '127.0.0.1'
      port = options[:port] || 1981
      @server_socket = TCPServer.new(host, port)
      puts_my_pid_with("Start Hobbit Server... #{host}:#{port}")

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
