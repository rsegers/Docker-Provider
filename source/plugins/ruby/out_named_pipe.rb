require 'fluent/plugin/output'

$pipe_handle = nil
module Fluent::Plugin
  class NamedPipeOutput < Output
    Fluent::Plugin.register_output('named_pipe', self)
    helpers :formatter
    config_param :datatype, :string

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
    end

    def format(tag, time, record)
      if record != {}
        return [tag, [[time, record]]].to_msgpack
      else
        return ""
      end
    end

    def shutdown
      super
      $pipe_handle.close
    end

    def write(chunk)
      begin
        if !$pipe_handle
          pipe_suffix = ExtensionUtils.getOutputNamedPipe(@datatype)
          if !pipe_suffix.nil? && !pipe_suffix.empty?
            pipe_name = "\\\\.\\pipe\\" + pipe_suffix
            @log.info "out_named_pipe::Named pipe: #{pipe_name}"
            $pipe_handle = File.open(pipe_name, File::WRONLY)
            @log.info "out_named_pipe::Pipe handle : #{$pipe_handle}"
          else
            @log.info "out_named_pipe::No pipe_suffix found. will be retried"
          end
        end
        if $pipe_handle
          @log.info "out_named_pipe::Writing for datatype: #{@datatype}"
          chunk.write_to($pipe_handle)
        else
          @log.error "out_named_pipe::No pipe handle"
        end
      rescue Exception => e
        @log.error "out_named_pipe::Exception when writing to named pipe: #{e}"
        if $pipe_handle
          $pipe_handle.close
          $pipe_handle = nil
        end
        raise e
      end
    end

    def process(tag, es)
      begin
        pipe_suffix = ExtensionUtils.getOutputNamedPipe(@datatype)
        if !pipe_suffix.nil? && !pipe_suffix.empty?
          pipe_name = "\\\\.\\pipe\\" + pipe_suffix
          @log.info "out_named_pipe::Named pipe: #{pipe_name} for datatype: #{@datatype}"
          pipe_handle = File.open(pipe_name, File::WRONLY)
          es.each do |time, record|
            bytes = pipe_handle.write @formatter.format(tag, time, record)
            @log.info "out_named_pipe::Data bytes sent: #{bytes} for datatype: #{@datatype}"
            pipe_handle.flush
          end
          pipe_handle.close
        else
          @log.error "out_named_pipe::Couldn't get pipe name from extension config for datatype: #{@datatype}. will be retried."
        end
      rescue Exception => e
        @log.error "out_named_pipe::Exception when writing to named pipe: #{e}"
        raise e
      end
    end
  end
end
