require 'fluent/plugin/output'

module Fluent::Plugin
  class NamedPipeOutput < Output
    Fluent::Plugin.register_output('named_pipe', self)

    helpers :formatter

    config_param :datatype, :string

    unless method_defined?(:log)
      define_method(:log) { $log }
    end

    def initialize
        super
        require_relative "extension_utils"
    
    end

    def configure(conf)
      super

      @formatter = formatter_create(usage: 'msgpack_formatter', type: 'msgpack' )
    end

    def start
      super
      begin
        @pipe_name = ExtensionUtils.getOutputNamedPipe(@datatype)
        @log.info "Named pipe: #{@pipe_name}"
        if !File.exist?(@pipe_name)
            @log.error "Pipe name doesn't exist"
        end
      rescue => e
        @log.info "exception while starting out_named_pipe #{e}"
      end
    end

    def format(tag, time, record)
        if record != {}
          @log.trace "Buffering #{tag}"
          return [tag, record].to_msgpack
        else
          return ""
        end
    end

        # This method is called every flush interval. Send the buffer chunk to MDM.
    # 'chunk' is a buffer chunk that includes multiple formatted records
    def write(chunk)
        begin
          @pipe = File.open(@pipe_name, File::WRONLY)
          chunk.extend Fluent::ChunkMessagePackEventStreamer
          chunk.msgpack_each { |(tag, record)|
              bytes = @pipe.write record
              @log.info "Data bytes sent: #{bytes}"
              @pipe.flush
          }
         
        rescue Exception => e
          @log.info "Exception when writing to named pipe: #{e}"
          raise e
        end
      end

#     def format(tag, time, record)
#       # 3. Call `format` method to format `record`
#       @formatter.format(tag, time, record)
#     end

#   def process(tag, es)
#     @pipe = File.open(@pipe_name, File::WRONLY)
#     es.each do |time, record|
#       recordArray = [time, record]
#       fluentMessage = [tag]
#       fluentMessage.append([recordArray])
#       @log.info "Formatted message is: #{fluentMessage}"
#       bytes = @pipe.write @formatter.format(tag, time, fluentMessage)
#       @log.info "Data bytes sent: #{bytes}"
#       @pipe.flush
#     end
  
#   rescue => e
#     log.error "out_named_pipe: unexpected error", :error_class => e.class, :error => e.to_s
#     log.error_backtrace
#   end

  end
end

