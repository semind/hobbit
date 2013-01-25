module Hobbit
  module Util
    def puts_my_pid_with(message)
      puts "PID: #{Process.pid} #{message}"
    end
  end
end
