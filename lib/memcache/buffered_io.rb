require 'net/protocol'

class MemCache
  class BufferedIO < Net::BufferedIO # :nodoc:
    # An implementation similar to this is in *trunk* for 1.9.  When it
    # gets released, this method can be removed when using 1.9
    def rbuf_fill
      begin
        @rbuf << @io.read_nonblock(BUFSIZE)
      rescue Errno::EWOULDBLOCK
        retry unless @read_timeout
        if IO.select([@io], nil, nil, @read_timeout)
          retry
        else
          raise Timeout::TimeoutError
        end
      end
    end

    def setsockopt *args
      @io.setsockopt *args
    end

    def gets
      readuntil("\n")
    end
  end
end
