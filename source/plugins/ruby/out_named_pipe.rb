require 'fluent/plugin/output'

module Fluent::Plugin
  class NamedPipeOutput < Output
    Fluent::Plugin.register_output('named_pipe', self)

    helpers :formatter

    config_param :datatype, :string

    def initialize
        super
        require_relative "extension_utils"
        @semaphore = Mutex.new
    end

    def configure(conf)
      super

      @formatter = formatter_create(usage: 'msgpack_formatter', type: 'msgpack' )
    end

    def start
      super
    end

    def format(tag, time, record)
      if record != {}
        return [tag, [[time, record]]].to_msgpack
      else
        return ""
      end
    end

    def write(chunk)
      end
      begin
        @semaphore.synchronize {
          pipe_suffix = ExtensionUtils.getOutputNamedPipe(@datatype)
          if !pipe_suffix.nil? && !pipe_suffix.empty?
            pipe_name = "\\\\.\\pipe\\" + pipe_suffix
            @log.info "Named pipe: #{pipe_name}"
            pipe_handle = File.open(pipe_name, File::WRONLY)
            chunk.write_to(pipe_handle)
            pipe_handle.flush
            pipe_handle.close
          else
            @log.error "Couldn't get pipe name from extension config. will be retried."
          end
        }
      rescue Exception => e
        @log.info "Exception when writing to named pipe: #{e}"
        raise e
      end
    end

  end
end