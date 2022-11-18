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
          outputStreamId = Extension.instance.get_output_stream_id(dataType)
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
      nameSpaces = []
      begin
        dataCollectionSettings = Extension.instance.get_extension_data_collection_settings()
        if !dataCollectionSettings.nil? &&
           !dataCollectionSettings.empty? &&
           dataCollectionSettings.has_key?(Constants::EXTENSION_SETTINGS_DATA_COLLECTION_SETTINGS_NAMESPACES)
          nameSpacesSetting = dataCollectionSettings[Constants::EXTENSION_SETTINGS_DATA_COLLECTION_SETTINGS_NAMESPACES]
          if !nameSpacesSetting.nil? && !nameSpacesSetting.empty? && nameSpacesSetting.kind_of?(Array) && nameSpacesSetting.length > 0
            uniqNamespaces = nameSpacesSetting.uniq
            nameSpaces = uniqNamespaces.map(&:downcase)
          else
            $log.warn("ExtensionUtils::getNamespacesForDataCollection: nameSpaces: #{nameSpacesSetting} not valid hence using default")
          end
        end
      rescue => errorStr
        $log.warn("ExtensionUtils::getNamespacesForDataCollection: failed with an exception: #{errorStr}")
      end
      return nameSpaces
    end

    def getNamespacesModeForDataCollection
      nameSpaceMode = "off"
      begin
        dataCollectionSettings = Extension.instance.get_extension_data_collection_settings()
        if !dataCollectionSettings.nil? &&
           !dataCollectionSettings.empty? &&
           dataCollectionSettings.has_key?(Constants::EXTENSION_SETTINGS_DATA_COLLECTION_SETTINGS_NAMESPACES_MODE)
          mode = dataCollectionSettings[Constants::EXTENSION_SETTINGS_DATA_COLLECTION_SETTINGS_NAMESPACES_MODE]
          if !mode.nil? && !mode.empty?
            nameSpaceMode = mode.downcase
            if !Constants::EXTENSION_SETTINGS_DATA_COLLECTION_SETTINGS_NAMESPACES_FILTERING_MODES.include?(nameSpaceMode)
              $log.warn("ExtensionUtils::getNamespacesModeForDataCollection: nameSpaceMode: #{mode} not supported hence using default")
            end
          else
            $log.warn("ExtensionUtils::getNamespacesModeForDataCollection: nameSpaceMode: #{mode} not valid hence using default")
          end
        end
      rescue => errorStr
        $log.warn("ExtensionUtils::getNamespacesModeForDataCollection: failed with an exception: #{errorStr}")
      end
      return nameSpaceMode
    end
  end
end
