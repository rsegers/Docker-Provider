require 'fluent/plugin/output'


module Fluent::Plugin
  class NamedPipeOutput < Output
    Fluent::Plugin.register_output('named_pipe', self)
    helpers :formatter
    config_param :datatype, :string
  
    def initialize
        super
        require_relative "extension_utils"
        require_relative "ApplicationInsightsUtility"
        @pipe_handle = nil
        @file_open_lock = Mutex.new
        @chunk_write_lock = Mutex.new
        @@namedPipeEventTelemetryTracker = DateTime.now.to_time.to_i
        @@properties = {}
    end

    def configure(conf)
      super
      @formatter = formatter_create(usage: 'msgpack_formatter', type: 'msgpack' )
    end

    def start
      super
      @@properties[@datatype] = 0
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
      @pipe_handle.close
    end

    def write(chunk)
      begin
        if !@pipe_handle
          @file_open_lock.synchronize {
            if !@pipe_handle #At the beginning, some other flush thread might have already got the handle so checking again if still not available. 
              pipe_suffix = ExtensionUtils.getOutputNamedPipe(@datatype)
              if !pipe_suffix.nil? && !pipe_suffix.empty?
                pipe_name = "\\\\.\\pipe\\" + pipe_suffix
                @log.info "out_named_pipe::Named pipe: #{pipe_name}"
                @pipe_handle = File.open(pipe_name, File::WRONLY)
                @log.info "out_named_pipe::Pipe handle : #{@pipe_handle}"
              else
                @log.info "out_named_pipe::No pipe_suffix found. will be retried"
              end
            end
          }
        end
        if @pipe_handle
          @log.info "out_named_pipe::Writing for datatype: #{@datatype}"
          @chunk_write_lock.synchronize {
            lock_file_path = '/etc/amalogswindows/filelock_ama'
            File.open(lock_file_path, File::CREAT|File::RDWR, 0666) do |lock_file|
              lock_file.flock(File::LOCK_EX)
              chunk.write_to(@pipe_handle)
              lock_file.flock(File::LOCK_UN)
            end
          }

          # Adding telemetry to send total events written to named pipe telemetry every 10 minutes
          timeDifference = (DateTime.now.to_time.to_i - @@namedPipeEventTelemetryTracker).abs
          telemetryFlush = false
          timeDifferenceInMinutes = timeDifference / 60
          if (timeDifferenceInMinutes >= 10)
            telemetryFlush = true
          end
          if telemetryFlush
            ApplicationInsightsUtility.sendCustomEvent("WindowsAMANamedPipeWriteEvent", @@properties)
            @@namedPipeEventTelemetryTracker = DateTime.now.to_time.to_i
          else
            @@properties[@datatype] += 1
          end
        else
          @log.error "out_named_pipe::No pipe handle"
        end
      rescue Exception => e
        @log.error "out_named_pipe::Exception when writing to named pipe: #{e}"
        ApplicationInsightsUtility.sendExceptionTelemetry(e, { "FeatureArea" => "NamedPipe" })
        if @pipe_handle
          @pipe_handle.close
          @pipe_handle = nil
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
