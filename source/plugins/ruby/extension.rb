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
    @cache = {}
    @datatype_to_stream_id_mapping = {}
    @datatype_to_named_pipe_mapping = {}
    @cache_lock = Mutex.new
    @clientNamedPipe = nil
    @clientNamedPipe_lock = Mutex.new
    $log.info("Extension::initialize complete")
  end

  def get_output_stream_id(datatypeId)
    @cache_lock.synchronize {
      if @datatype_to_stream_id_mapping.has_key?(datatypeId)
        return @datatype_to_stream_id_mapping[datatypeId]
      else
        @datatype_to_stream_id_mapping = get_stream_mapping()
        return @datatype_to_stream_id_mapping[datatypeId]
      end
    }
  end

  def get_output_named_pipe(datatypeId)
    if @datatype_to_named_pipe_mapping.has_key?(datatypeId)
      return @datatype_to_named_pipe_mapping[datatypeId]
    else
      @datatype_to_named_pipe_mapping = get_namedpipe_mapping()
      return @datatype_to_named_pipe_mapping[datatypeId]
    end
  end

  def get_extension_settings()
    extensionSettings = Hash.new
    begin
      extensionConfigurations = get_extension_configs()
      if !extensionConfigurations.nil? && !extensionConfigurations.empty?
        extensionConfigurations.each do |extensionConfig|
          if !extensionConfig.nil? && !extensionConfig.empty?
            extSettings = extensionConfig[Constants::EXTENSION_SETTINGS]
            if !extSettings.nil? && !extSettings.empty?
              extensionSettings = extSettings
            end
          end
        end
      end
    rescue =>errorStr
      $log.warn("Extension::get_extension_settings failed: #{errorStr}")
      ApplicationInsightsUtility.sendExceptionTelemetry(errorStr)
    end
    return extensionSettings
  end

  def get_extension_data_collection_settings()
    dataCollectionSettings = Hash.new
    begin
      extensionSettings = get_extension_settings()
      if !extensionSettings.nil? && !extensionSettings.empty?
        dcSettings = extensionSettings[Constants::EXTENSION_SETTINGS_DATA_COLLECTION_SETTINGS]
        if !dcSettings.nil? && !dcSettings.empty?
          dataCollectionSettings = dcSettings
        end
      end
    rescue =>errorStr
      $log.warn("Extension::get_extension_data_collection_settings failed: #{errorStr}")
      ApplicationInsightsUtility.sendExceptionTelemetry(errorStr)
    end
    return dataCollectionSettings
  end


  def get_stream_mapping()
     dataTypeToStreamIdMap = Hash.new
     begin
      extensionConfigurations = get_extension_configs()
      if !extensionConfigurations.nil? && !extensionConfigurations.empty?
        extensionConfigurations.each do |extensionConfig|
          outputStreams = extensionConfig["outputStreams"]
          if !outputStreams.nil? && !outputStreams.empty?
            outputStreams.each do |datatypeId, streamId|
              dataTypeToStreamIdMap[datatypeId] = streamId
            end
          else
            $log.warn("Extension::get_stream_mapping::received outputStreams is either nil or empty")
          end
        end
      else
        $log.warn("Extension::get_stream_mapping::received extensionConfigurations either nil or empty")
      end
     rescue => errorStr
      $log.warn("Extension::get_stream_mapping failed: #{errorStr}")
      ApplicationInsightsUtility.sendExceptionTelemetry(errorStr)
     end
     return dataTypeToStreamIdMap
  end

  def get_namedpipe_mapping()
    dataTypeToNamedPipeMap = Hash.new
    begin
     taggedAgentData = get_extension_configs(true)
     if !taggedAgentData.nil? && !taggedAgentData.empty?
      extensionConfigurations = taggedAgentData["extensionConfigurations"]
      outputStreamDefinitions = taggedAgentData["outputStreamDefinitions"]
      if !extensionConfigurations.nil? && !extensionConfigurations.empty?
        extensionConfigurations.each do |extensionConfig|
          outputStreams = extensionConfig["outputStreams"]
          if !outputStreams.nil? && !outputStreams.empty?
            outputStreams.each do |datatypeId, streamId|
            dataTypeToNamedPipeMap[datatypeId] = outputStreamDefinitions[streamId]["namedPipe"]
            end
          else
            $log.warn("Extension::get_namedpipe_mapping::received outputStreams or outputStreamDefinitions is either nil or empty")
          end
        end
      else
        $log.warn("Extension::get_namedpipe_mapping::received extensionConfigurations either nil or empty")
      end
     else
      $log.warn("Extension::get_namedpipe_mapping::received taggedAgentData either nil or empty")
     end
    rescue => errorStr
     $log.warn("Extension::get_namedpipe_mapping failed: #{errorStr}")
     ApplicationInsightsUtility.sendExceptionTelemetry(errorStr)
    end
    return dataTypeToNamedPipeMap
 end


  private
  def get_extension_configs(getTaggedAgentData = false)
    extensionConfigurations = []
    begin
      requestId = SecureRandom.uuid.to_s
      requestBodyJSON = { "Request" => "AgentTaggedData", "RequestId" => requestId, "Tag" => Constants::CI_EXTENSION_NAME, "Version" => Constants::CI_EXTENSION_VERSION }.to_json
      if !@@isWindows.nil? && @@isWindows == false
        clientSocket = UNIXSocket.open(Constants::ONEAGENT_FLUENT_SOCKET_NAME)
        requestBodyMsgPack = requestBodyJSON.to_msgpack
        clientSocket.write(requestBodyMsgPack)
        clientSocket.flush
        resp = clientSocket.recv(Constants::CI_EXTENSION_CONFIG_MAX_BYTES)
      else
        begin
          if !@clientNamedPipe
            configPipe = "\\\\.\\pipe\\CAgentStream_CloudAgentInfo_AzureMonitorAgent"
              @clientNamedPipe = File.open(configPipe, "w+")
          end
          resp = ''
          @clientNamedPipe_lock.synchronize {
              @clientNamedPipe.write(requestBodyJSON)
              @clientNamedPipe.sysread(Constants::CI_EXTENSION_CONFIG_MAX_BYTES, resp)
          }
        rescue Exception => e
          $log.info "Extension::get_extension_configs Exception when connecting to named pipe: #{e}"
          if @clientNamedPipe
            @clientNamedPipe.close
            @clientNamedPipe = nil
          end
          raise e
        end
      end
      if !resp.nil? && !resp.empty?
        respJSON = JSON.parse(resp)
        taggedData = respJSON["TaggedData"]
        if !taggedData.nil? && !taggedData.empty?
          taggedAgentData = JSON.parse(taggedData)
          extensionConfigurations = taggedAgentData["extensionConfigurations"]
        end
      end
    rescue => errorStr
      $log.warn("Extension::get_extension_configs failed: #{errorStr}")
      ApplicationInsightsUtility.sendExceptionTelemetry(errorStr)
    ensure
      clientSocket.close unless clientSocket.nil?
    end
    if getTaggedAgentData == true
      return taggedAgentData
    end
    return extensionConfigurations
  end
end
