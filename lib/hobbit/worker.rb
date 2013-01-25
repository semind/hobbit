module Hobbit
  class Worker
    include Util

    def initialize(app, fd_recv)
      @app = app
      @fd_recv = fd_recv

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

      @parser = Http::Parser.new
      @parser_state = true # true => while parsing, false => not parsing

      # if parsing finished, then change state not parsing
      @parser.on_message_complete = proc do |env|
        @parser_state = false
      end
    end

    def wait_request
      loop do
        client_socket = dequeue_client
        handle_request(client_socket)
      end
    end

    # get request and response
    def handle_request(client_socket)
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

    # for dequeue client socket at worker process
    def dequeue_client
      @fd_recv.recv_io
    end

  end
end
