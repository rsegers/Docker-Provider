require "socket"
require "msgpack"
require "securerandom"
require "singleton"
require_relative "omslog"
require_relative "constants"
require_relative "ApplicationInsightsUtility"


class Extension
  include Singleton

  @@isWindows = false
  @@os_type = ENV["OS_TYPE"]
  if !@@os_type.nil? && !@@os_type.empty? && @@os_type.strip.casecmp("windows") == 0
    @@isWindows = true
  end

  def initialize
    @datatype_to_stream_id_mapping = {}
    @datatype_to_named_pipe_mapping = {}
    @cache_lock = Mutex.new
    $log.info("Extension::initialize complete")
  end

  def get_output_stream_id(datatypeId)
    @cache_lock.synchronize {
      if @datatype_to_stream_id_mapping.has_key?(datatypeId)
        return @datatype_to_stream_id_mapping[datatypeId]
      else
        @datatype_to_stream_id_mapping = get_config(false)
        return @datatype_to_stream_id_mapping[datatypeId]
      end
    }
  end

  def get_output_named_pipe(datatypeId)
    @cache_lock.synchronize {
      if @datatype_to_named_pipe_mapping.has_key?(datatypeId)
        return @datatype_to_named_pipe_mapping[datatypeId]
      else
        @datatype_to_named_pipe_mapping = get_config(true)
        return @datatype_to_named_pipe_mapping[datatypeId]
      end
    }
  end

  private
  def get_config(isNamedPipe)
    extConfig = Hash.new
    $log.info("Extension::get_config start ...")
    begin
      requestId = SecureRandom.uuid.to_s
      requestBodyJSON = { "Request" => "AgentTaggedData", "RequestId" => requestId, "Tag" => Constants::CI_EXTENSION_NAME, "Version" => Constants::CI_EXTENSION_VERSION }.to_json
      $log.info("Extension::get_config::sending request with request body: #{requestBodyJSON}")
      if !@@isWindows.nil? && @@isWindows == false
        clientSocket = UNIXSocket.open(Constants::ONEAGENT_FLUENT_SOCKET_NAME)
        requestBodyMsgPack = requestBodyJSON.to_msgpack
        clientSocket.write(requestBodyMsgPack)
        clientSocket.flush
        $log.info("reading the response from fluent socket: #{Constants::ONEAGENT_FLUENT_SOCKET_NAME}")
        resp = clientSocket.recv(Constants::CI_EXTENSION_CONFIG_MAX_BYTES)
      else
        configPipe = "\\\\.\\pipe\\CAgentStream_CloudAgentInfo_AzureMonitorAgent"
        clientNamedPipe = File.open(configPipe, "w+")
        clientNamedPipe.write(requestBodyJSON)
        resp = ''
        clientNamedPipe.sysread(Constants::CI_EXTENSION_CONFIG_MAX_BYTES, resp)
      end
      if !resp.nil? && !resp.empty?
        $log.info("Extension::get_config::successfully read the extension config from fluentsocket and number of bytes read is #{resp.length}")
        respJSON = JSON.parse(resp)
        taggedData = respJSON["TaggedData"]
        if !taggedData.nil? && !taggedData.empty?
          taggedAgentData = JSON.parse(taggedData)
          extensionConfigurations = taggedAgentData["extensionConfigurations"]
	        if isNamedPipe == true 
		        outputStreamDefinitions = taggedAgentData["outputStreamDefinitions"]
          end
          if !extensionConfigurations.nil? && !extensionConfigurations.empty?
            extensionConfigurations.each do |extensionConfig|
              outputStreams = extensionConfig["outputStreams"]
              if !outputStreams.nil? && !outputStreams.empty?
                outputStreams.each do |datatypeId, streamId|
                  $log.info("Extension::get_config datatypeId:#{datatypeId}, streamId: #{streamId}")
                  if !isNamedPipe
                    extConfig[datatypeId] = streamId
                  else
                    extConfig[datatypeId] = outputStreamDefinitions[streamId]["namedPipe"]
                end
              else
                $log.warn("Extension::get_config::received outputStreams is either nil or empty")
              end
            end
          else
            $log.warn("Extension::get_config::received extensionConfigurations from fluentsocket is either nil or empty")
          end
        end
      end
    rescue => errorStr
      $log.warn("Extension::get_config failed: #{errorStr}")
      ApplicationInsightsUtility.sendExceptionTelemetry(errorStr)
    ensure
      clientSocket.close unless clientSocket.nil?
    end
    $log.info("Extension::get_config complete ...")
    return extConfig
  end
end
