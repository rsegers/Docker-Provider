# Copyright (c) Microsoft Corporation.  All rights reserved.
#!/usr/local/bin/ruby
# frozen_string_literal: true

require_relative "extension"
require_relative "constants"

class ExtensionUtils
  class << self
    def getOutputStreamId(dataType)
      outputStreamId = ""
      begin
        if !dataType.nil? && !dataType.empty?
          dataTypeToStreamIdMap = Extensio.instance.get_stream_mapping()
          if !dataTypeToStreamIdMap.nil? && dataTypeToStreamIdMap.has_key?(dataType)
            outputStreamId = dataTypeToStreamIdMap[dataType]
          end
          $log.info("ExtensionUtils::getOutputStreamId: got streamid: #{outputStreamId} for datatype: #{dataType}")
        else
          $log.warn("ExtensionUtils::getOutputStreamId: dataType shouldnt be nil or empty")
        end
      rescue => errorStr
        $log.warn("ExtensionUtils::getOutputStreamId: failed with an exception: #{errorStr}")
      end
      return outputStreamId
    end

    def isAADMSIAuthMode()
      return !ENV["AAD_MSI_AUTH_MODE"].nil? && !ENV["AAD_MSI_AUTH_MODE"].empty? && ENV["AAD_MSI_AUTH_MODE"].downcase == "true"
    end

    def isDataCollectionSettingsConfigured
      isCollectionSettingsEnabled = false
      begin
        dataCollectionSettings = Extension.instance.get_extension_data_collection_settings()
        if !dataCollectionSettings.nil? && !dataCollectionSettings.empty?
          isCollectionSettingsEnabled = true
        end
      rescue => errorStr
        $log.warn("ExtensionUtils::isDataCollectionSettingsConfigured: failed with an exception: #{errorStr}")
      end
      return isCollectionSettingsEnabled
    end

    def getDataCollectionIntervalSeconds
      collectionIntervalSeconds = 60
      begin
        dataCollectionSettings = Extension.instance.get_extension_data_collection_settings()
        if !dataCollectionSettings.nil? &&
           !dataCollectionSettings.empty? &&
           dataCollectionSettings.has_key?(Constants::EXTENSION_SETTINGS_DATA_COLLECTION_SETTINGS_INTERVAL)
          interval = dataCollectionSettings[Constants::EXTENSION_SETTINGS_DATA_COLLECTION_SETTINGS_INTERVAL]
          re = /^[0-9]+[m]$/
          if !re.match(interval).nil?
            intervalMinutes = interval.dup.chomp!("m").to_i
            if intervalMinutes.between?(Constants::EXTENSION_SETTINGS_DATA_COLLECTION_SETTINGS_INTERVAL_MIN, Constants::EXTENSION_SETTINGS_DATA_COLLECTION_SETTINGS_INTERVAL_MAX)
              collectionIntervalSeconds = intervalMinutes * 60
            else
              $log.warn("ExtensionUtils::getDataCollectionIntervalSeconds: interval value not in the range 1m to 30m hence using default, 60s: #{errorStr}")
            end
          else
            $log.warn("ExtensionUtils::getDataCollectionIntervalSeconds: interval value is invalid hence using default, 60s: #{errorStr}")
          end
        end
      rescue => errorStr
        $log.warn("ExtensionUtils::getDataCollectionIntervalSeconds: failed with an exception: #{errorStr}")
      end
      return collectionIntervalSeconds
    end

    def getNamespacesForDataCollection
      namespaces = []
      begin
        dataCollectionSettings = Extension.instance.get_extension_data_collection_settings()
        if !dataCollectionSettings.nil? &&
           !dataCollectionSettings.empty? &&
           dataCollectionSettings.has_key?(Constants::EXTENSION_SETTINGS_DATA_COLLECTION_SETTINGS_NAMESPACES)
          namespacesSetting = dataCollectionSettings[Constants::EXTENSION_SETTINGS_DATA_COLLECTION_SETTINGS_NAMESPACES]
          if !namespacesSetting.nil? && !namespacesSetting.empty? && namespacesSetting.kind_of?(Array) && namespacesSetting.length > 0
            uniqNamespaces = namespacesSetting.uniq
            namespaces = uniqNamespaces.map(&:downcase)
          else
            $log.warn("ExtensionUtils::getNamespacesForDataCollection: namespaces: #{namespacesSetting} not valid hence using default")
          end
        end
      rescue => errorStr
        $log.warn("ExtensionUtils::getNamespacesForDataCollection: failed with an exception: #{errorStr}")
      end
      return namespaces
    end

    def getNamespaceFilteringModeForDataCollection
      namespaceFilteringMode = "off"
      begin
        dataCollectionSettings = Extension.instance.get_extension_data_collection_settings()
        if !dataCollectionSettings.nil? &&
           !dataCollectionSettings.empty? &&
           dataCollectionSettings.has_key?(Constants::EXTENSION_SETTINGS_DATA_COLLECTION_SETTINGS_NAMESPACE_FILTERING_MODE)
          mode = dataCollectionSettings[Constants::EXTENSION_SETTINGS_DATA_COLLECTION_SETTINGS_NAMESPACE_FILTERING_MODE]
          if !mode.nil? && !mode.empty?
            if Constants::EXTENSION_SETTINGS_DATA_COLLECTION_SETTINGS_NAMESPACE_FILTERING_MODES.include?(mode.downcase)
              namespaceFilteringMode = mode.downcase
            else
              $log.warn("ExtensionUtils::getNamespaceFilteringModeForDataCollection: namespaceFilteringMode: #{mode} not supported hence using default")
            end
          else
            $log.warn("ExtensionUtils::getNamespaceFilteringModeForDataCollection: namespaceFilteringMode: #{mode} not valid hence using default")
          end
        end
      rescue => errorStr
        $log.warn("ExtensionUtils::getNamespaceFilteringModeForDataCollection: failed with an exception: #{errorStr}")
      end
      return namespaceFilteringMode
    end

    def getDataCollectionProfile
      begin
        dataCollectionStreamProfile = "Default"
        dataTypes = []
        dataTypeToStreamIdMap = Extensio.instance.get_stream_mapping()
        if !dataTypeToStreamIdMap.nil? && !dataTypeToStreamIdMap.empty?
          dataTypes = dataTypeToStreamIdMap.keys
          if (dataTypes.length == 12)
            dataCollectionStreamProfile = "Default"
          elsif ((dataTypes.length <= 3) && (dataTypes.include?("CONTAINER_LOG_BLOB") || dataTypes.include?("CONTAINERINSIGHTS_CONTAINERLOGV2")) && dataTypes.include?("KUBE_EVENTS_BLOB"))
            dataCollectionStreamProfile = "LogsAndEvents"
          elsif (dataTypes.length == 2) && dataTypes.include?("LINUX_PERF_BLOB") && dataTypes.include?("INSIGHTS_METRICS_BLOB")
            dataCollectionStreamProfile = "Performance"
          elsif (dataTypes.length == 2) && dataTypes.include?("INSIGHTS_METRICS_BLOB") && dataTypes.include?("KUBE_PV_INVENTORY_BLOB")
            dataCollectionStreamProfile = "PV"
          elsif (dataTypes.length == 8) && dataTypes.include?("INSIGHTS_METRICS_BLOB") && dataTypes.include?("KUBE_POD_INVENTORY_BLOB") &&
                dataTypes.include?("KUBE_NODE_INVENTORY_BLOB") && dataTypes.include?("KUBE_EVENTS_BLOB") &&
                dataTypes.include?("CONTAINER_INVENTORY_BLOB") && dataTypes.include?("CONTAINER_NODE_INVENTORY_BLOB") &&
                dataTypes.include?("KUBE_NODE_INVENTORY_BLOB") && dataTypes.include?("KUBE_SERVICES_BLOB")
            dataCollectionStreamProfile = "Workload,Deployments,and HPAs"
          else
            dataCollectionStreamProfile = "Custom"
          end
        end
      rescue => errorStr
        $log.warn("ExtensionUtils::getDataCollectionProfile: failed with an exception: #{errorStr}")
      end
      return dataCollectionStreamProfile
    end
  end
end
