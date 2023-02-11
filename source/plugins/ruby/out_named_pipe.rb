require 'fluent/plugin/output'

module Fluent::Plugin
  class NamedPipeOutput < Output
    Fluent::Plugin.register_output('named_pipe', self)

    helpers :formatter

    config_param :datatype, :string

    def initialize
        super
        require_relative "extension_utils"

        @pipe_name = ""
        @pipe_handle = nil

    end

    def configure(conf)
      super

      @formatter = formatter_create(usage: 'msgpack_formatter', type: 'msgpack' )
    end

    def getNamedPipeFromExtension()
        pipe_suffix = ExtensionUtils.getOutputNamedPipe(@datatype)
        if !pipe_suffix.nil? && !pipe_suffix.empty?
          @pipe_name = "\\\\.\\pipe\\" + pipe_suffix
          @log.info "Named pipe: #{@pipe_name}"
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
        # if record != {}
        #   return [tag, [[time, record]]].to_msgpack
        # else
        #   return ""
        # end
        @formatter.format(tag, time, record)
    end

    def process(tag, es)
      if @pipe_name.nil? || @pipe_name.empty?
        getNamedPipeFromExtension()
      end
      begin
        if @pipe_name.nil? || @pipe_name.empty?
          @log.info "Cannot create pipe handle skipping"
        else
          @pipe_handle = File.open(@pipe_name, File::WRONLY)
          es.each do |time, record|
            recordArray = [time, record]
            fluentMessage = [tag]
            fluentMessage.append([recordArray])
            @log.info "Formatted message is: #{fluentMessage}"
            bytes = @pipe_handle.write @formatter.format(tag, time, fluentMessage)
            @log.info "Data bytes sent: #{bytes}"
            @pipe_handle.flush
          end
          @pipe_handle.close()
        end
      rescue Exception => e
        @log.info "Exception when writing to named pipe: #{e}"
        raise e
      end
    end


    # def write(chunk)
    #   if @pipe_name.nil? || @pipe_name.empty?
    #     getNamedPipeFromExtension()
    #   end
    #   begin
    #     @pipe_handle = File.open(@pipe_name, File::WRONLY)
    #     chunk.write_to(@pipe_handle)
    #     @pipe_handle.flush
    #     @pipe_handle.close
    #   rescue Exception => e
    #     @log.info "Exception when writing to named pipe: #{e}"
    #     raise e
    #   end
    # end

  end
end