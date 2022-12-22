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

    def getNamedPipeFromExtension()
        @pipe_name = ""
        pipe_suffix = ExtensionUtils.getOutputNamedPipe(@datatype)
        if !pipe_suffix.nil? && !pipe_suffix.empty?
          @pipe_name = "\\\\.\\pipe\\" + @name
          @log.info "Named pipe: #{pipe_name}"
        end
    end

    def start
      super
      begin
        getNamedPipeFromExtension()    
        if @pipe_name.nil? || @pipe_name.empty?
            @log.error "Couldn't get pipe name from extension config. Will retry during write"
        elsif !File.exist?(@pipe_name)
            @log.error "Named pipe with name: #{@pipe_name} doesn't exist"
        end
      rescue => e
        @log.info "Exception while starting out_named_pipe #{e}"
      end
    end

    def format(tag, time, record)
        if record != {}
          return [tag, [[time, record]]].to_msgpack
        else
          return ""
        end
    end

        # This method is called every flush interval. Send the buffer chunk to MDM.
    # 'chunk' is a buffer chunk that includes multiple formatted records
    def write(chunk)
        while !@pipe_name.nil? && !@pipe_name.empty?
            sleep 5
            getNamedPipeFromExtension()
        end

        begin
          @pipe = File.open(@pipe_name, File::WRONLY)
          chunk.write_to(@pipe)
          @pipe.flush
          @pipe.close
        #   chunk.extend Fluent::ChunkMessagePackEventStreamer
        #   chunk.msgpack_each { |(tag, record)|
        #       bytes = @pipe.write [tag, [record]].to_msgpack
        #       @log.info "Data bytes sent: #{bytes}"
        #       @pipe.flush
        #   }
         
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