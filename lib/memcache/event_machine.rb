# Extensions for using memcache-client with EventMachine

raise "memcache/event_machine requires Ruby 1.9" if RUBY_VERSION < '1.9'

require 'fiber'

class MemCache::Server
  
  alias :blocking_socket :socket
    
  def socket
    # Support plain old TCP socket connections if the user
    # has not setup EM.  Much easier to deal with in irb, 
    # script/console, etc.
    return blocking_socket if !EM.reactor_running?

    return @sock if @sock and not @sock.closed?

    @sock = nil

    # If the host was dead, don't retry for a while.
    return if @retry and @retry > Time.now
    
    fiber = Fiber.current
    @sock = EM::SocketConnection.connect(@host, @port, @timeout)
    yielding = true
    @sock.callback do
      @status = 'CONNECTED'
      @retry  = nil
      yielding = false
      fiber.resume if Fiber.current != fiber
    end
    @sock.errback do
      yielding = false
      fiber.resume if Fiber.current != fiber
    end
    Fiber.yield if yielding
    @sock
  end
  
end

module EM
  module SocketConnection
    include EM::Deferrable

    def self.connect(host, port, timeout)
      EM.connect(host, port, self) do |conn|
        conn.pending_connect_timeout = timeout
      end
    end

    def initialize
      @connected = false
      @index = 0
      @buf = ''
    end

    def closed?
      !@connected
    end

    def close
      @connected = false
      close_connection(true)
    end

    def write(buf)
      send_data(buf)
    end

    def read(size)
      if can_read?(size)
        yank(size)
      else
        fiber = Fiber.current
        @size = size
        @callback = proc { |data|
          fiber.resume(data)
        }
        # TODO Can leak fiber if the connection dies while
        # this fiber is yielded, waiting for data
        Fiber.yield
      end
    end
    
    SEP = "\r\n"

    def gets
      while true
        # Read to ensure we have some data in the buffer
        line = read(2)
        # Reset the buffer index to zero
        @buf = @buf.slice(@index..-1)
        @index = 0
        if eol = @buf.index(SEP)
          line << yank(eol + SEP.size)
          break
        else
          # EOL not in the current buffer
          line << yank(@buf.size)
        end
      end
      line
    end

    def can_read?(size)
      @buf.size >= @index + size
    end

    # EM callbacks

    def receive_data(data)
      @buf << data

      if @callback and can_read?(@size)
        callback = @callback
        data = yank(@size)
        @callback = @size = nil
        callback.call(data)
      end
    end

    def post_init
      @connected = true
      succeed
    end

    def unbind
      @connected = false
    end
    
    private
    
    BUFFER_SIZE = 4096

    def yank(len)      
      data = @buf.slice(@index, len)
      @index += len
      @index = @buf.size if @index > @buf.size
      if @index >= BUFFER_SIZE
        @buf = @buf.slice(@index..-1)
        @index = 0
      end
      data
    end
    
  end
end