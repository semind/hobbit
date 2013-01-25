require 'rack'

module Hobbit
  attr_accessor :app
  attr_accessor :server_socket
  class Server
    def initialize(app, options = {})
      ## params need to define before fork worker process
      @app = app # Rack

      # Socket Pair for pass client socket to worker process
      @fd_send, @fd_recv = UNIXSocket.pair

      empty_body = ''
      empty_body.encode!(Encoding::ASCII_8BIT) if empty_body.respond_to?(:encode!)
      @env = {
        'rack.input' => StringIO.new(empty_body),
        'rack.errors' => STDERR,
        'rack.multithread' => false,
        'rack.multiprocess' => false,
        'rack.run_once' => true,
        'rack.url_scheme' => 'http',
        'rack.version' => [1, 0]
      }

      @worker_pids = []

      @parser = Http::Parser.new
      @parser_state = true # true => while parsing, false => not parsing

      # if parsing finished, then change state not parsing
      @parser.on_message_complete = proc do |env|
        @parser_state = false
      end

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

    # get request and response
    def handle_request
      loop do
        client_socket = dequeue_client
        puts_my_pid_with("handle rquest")

        env = initialize_state

        parse_request(client_socket)
        env = normalize_rack_env(env)

        # excute application
        status, headers, body = @app.call(env)

        # write response header to client
        response_header = normalize_response_header(status, headers)
        client_socket.write(response_header)

        # write response body to client
        body.each do |part|
          client_socket.write part
        end
        body.close if body.respond_to?(:close)

        client_socket.flush
        client_socket.close
      end
    end

    def initialize_state
      env = @env.dup
      @parser.reset!
      @parser_state = true
      env
    end

    def parse_request(client_socket)
      request = client_socket.readpartial(16 * 1024)
      @parser << request

      # wait parsing finished
      while @parser_state
        puts "parsing"
      end
    end

    def normalize_rack_env(env)
      # append key/value Rack required
      env['REQUEST_METHOD'] = @parser.http_method
      host, port = @parser.headers['Host'].split(/:/)
      env['SERVER_NAME']  = host
      env['SERVER_PORT']  = port
      env['QUERY_STRING'] = @parser.query_string
      env['PATH_INFO'] = @parser.request_path
      env
    end

    # generate response header
    def normalize_response_header(status, headers)
      response = "HTTP/1.1 #{status}\r\n" \
                 "Date: #{Time.now.httpdate}\r\n" \
                 "Status: #{Rack::Utils::HTTP_STATUS_CODES[status]}\r\n" \
                 "Connection: close\r\n"

      headers.each do |k,v|
        response << "#{k}: #{v}\r\n"
      end
      response += "\r\n"
    end

    def puts_my_pid_with(message)
      puts "PID: #{Process.pid} #{message}"
    end

    # for enqueue client socket at master process
    def enqueue_client(client_socket)
      @fd_send.send_io client_socket
    end

    # for dequeue client socket at worker process
    def dequeue_client
      @fd_recv.recv_io
    end

    def spawn_worker
      @worker_pids << fork do
        handle_request
      end
    end

  end
end
