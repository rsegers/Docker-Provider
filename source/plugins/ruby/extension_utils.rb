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
              interval =  dataCollectionSettings[Constants::EXTENSION_SETTINGS_DATA_COLLECTION_SETTINGS_INTERVAL]
              re = /^[0-9]+[m]$/              
              if !re.match(interval).nil?
                 intervalMinutes =  interval.dup.chomp!("m").to_i
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

        def getNamespacesToExcludeForDataCollection
          excludeNameSpaces = []
          begin
            dataCollectionSettings = Extension.instance.get_extension_data_collection_settings()
             if !dataCollectionSettings.nil? && 
              !dataCollectionSettings.empty? && 
              dataCollectionSettings.has_key?(Constants::EXTENSION_SETTINGS_DATA_COLLECTION_SETTINGS_EXCLUDE_NAMESPACES)
               namespacesToExclude = dataCollectionSettings[Constants::EXTENSION_SETTINGS_DATA_COLLECTION_SETTINGS_EXCLUDE_NAMESPACES]
               if !namespacesToExclude.nil? && !namespacesToExclude.empty? && namespacesToExclude.kind_of?(Array) && namespacesToExclude.length > 0 
                 uniqNamespaces = namespacesToExclude.uniq                 
                 excludeNameSpaces = uniqNamespaces.map(&:downcase)
              else 
                $log.warn("ExtensionUtils::getNamespacesToExcludeForDataCollection: excludeNameSpaces: #{namespacesToExclude} not valid hence using default")                   
               end             
             end
          rescue => errorStr 
            $log.warn("ExtensionUtils::getNamespacesToExcludeForDataCollection: failed with an exception: #{errorStr}")
          end
          return excludeNameSpaces
        end          

    end
end
