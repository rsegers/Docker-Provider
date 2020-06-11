#!/usr/local/bin/ruby

#this should be require relative in Linux and require in windows, since it is a gem install on windows
@os_type = ENV["OS_TYPE"]
if !@os_type.nil? && !@os_type.empty? && @os_type.strip.casecmp("windows") == 0
  require "tomlrb"
else
  require_relative "tomlrb"
end

require_relative "ConfigParseErrorLogger"

@configMapMountPath = "/etc/config/settings/agent-settings"
@configSchemaVersion = ""
@enable_health_model = false

# Use parser to parse the configmap toml file to a ruby structure
def parseConfigMap
  begin
    # Check to see if config map is created
    if (File.file?(@configMapMountPath))
      puts "config::configmap container-azm-ms-agentconfig for agent health settings mounted, parsing values"
      parsedConfig = Tomlrb.load_file(@configMapMountPath, symbolize_keys: true)
      puts "config::Successfully parsed mounted config map"
      return parsedConfig
    else
      puts "config::configmap container-azm-ms-agentconfig for agent health settings not mounted, using defaults"
      return nil
    end
  rescue => errorStr
    ConfigParseErrorLogger.logError("Exception while parsing config map for enabling health: #{errorStr}, using defaults, please check config map for errors")
    return nil
  end
end

# Use the ruby structure created after config parsing to set the right values to be used as environment variables
def populateSettingValuesFromConfigMap(parsedConfig)
  begin
    if !parsedConfig.nil? && !parsedConfig[:agent_settings].nil? && !parsedConfig[:agent_settings][:health_model].nil? && !parsedConfig[:agent_settings][:health_model][:enabled].nil?
        @enable_health_model = parsedConfig[:agent_settings][:health_model][:enabled]
        puts "enable_health_model = #{@enable_health_model}"
    end
  rescue => errorStr
    puts "config::error:Exception while reading config settings for health_model enabled setting - #{errorStr}, using defaults"
    @enable_health_model = false
  end
end

@configSchemaVersion = ENV["AZMON_AGENT_CFG_SCHEMA_VERSION"]
puts "****************Start Config Processing********************"
if !@configSchemaVersion.nil? && !@configSchemaVersion.empty? && @configSchemaVersion.strip.casecmp("v1") == 0 #note v1 is the only supported schema version , so hardcoding it
  configMapSettings = parseConfigMap
  if !configMapSettings.nil?
    populateSettingValuesFromConfigMap(configMapSettings)
  end
else
  if (File.file?(@configMapMountPath))
    ConfigParseErrorLogger.logError("config::unsupported/missing config schema version - '#{@configSchemaVersion}' , using defaults, please use supported schema version")
  end
  @enable_health_model = false
end

# Write the settings to file, so that they can be set as environment variables
file = File.open("health_config_env_var", "w")

if !file.nil?
  file.write("export AZMON_CLUSTER_ENABLE_HEALTH_MODEL=#{@enable_health_model}\n")
  # Close file after writing all environment variables
  file.close
else
  puts "Exception while opening file for writing config environment variables"
  puts "****************End Config Processing********************"
end