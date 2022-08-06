require "socket"
require "msgpack"
require "securerandom"
require "singleton"
require_relative "omslog"
require_relative "constants"
require_relative "ApplicationInsightsUtility"


class Extension
  include Singleton

  def initialize
    @cache = {}
    @cache_lock = Mutex.new
    $log.info("Extension::initialize complete")
  end

  def get_output_stream_id(datatypeId)
    @cache_lock.synchronize {
      if @cache.has_key?(datatypeId)
        return @cache[datatypeId]
      else
        @cache = get_stream_mapping()
        return @cache[datatypeId]
      end
    }
  end

  def get_extension_settings()
    extensionSettings = Hash.new 
    begin
      extensionConfigurations = get_extension_configs()
      if !extensionConfigurations.nil? && !extensionConfigurations.empty?
        extensionConfigurations.each do |extensionConfig|
          extSettings = extensionConfig[Constants::EXTENSION_SETTINGS]
          if !extSettings.nil? && !extSettings.empty?          
            extensionSettings = extSettings
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

  private
  def get_extension_configs()
    extensionConfigurations = []    
    begin
      clientSocket = UNIXSocket.open(Constants::ONEAGENT_FLUENT_SOCKET_NAME)
      requestId = SecureRandom.uuid.to_s
      requestBodyJSON = { "Request" => "AgentTaggedData", "RequestId" => requestId, "Tag" => Constants::CI_EXTENSION_NAME, "Version" => Constants::CI_EXTENSION_VERSION }.to_json      
      requestBodyMsgPack = requestBodyJSON.to_msgpack
      clientSocket.write(requestBodyMsgPack)
      clientSocket.flush      
      resp = clientSocket.recv(Constants::CI_EXTENSION_CONFIG_MAX_BYTES)
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
    return extensionConfigurations
  end
end
