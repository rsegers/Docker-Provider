#!/usr/local/bin/rubyinfra_namespaces

@os_type = ENV["OS_TYPE"]
require "tomlrb"

require_relative "ConfigParseErrorLogger"

@configMapMountPath = "/etc/config/settings/integrations"
@configSchemaVersion = ""
@geneva_logs_integration = false
@multi_tenancy = false

GENEVA_SUPPORTED_ENVIRONMENTS = ["Test", "Stage", "DiagnosticsProd", "FirstpartyProd", "BillingProd", "ExternalProd", "CaMooncake", "CaFairfax", "CaBlackforest"]
@geneva_account_environment = "" # Supported values Test, Stage, DiagnosticsProd, FirstpartyProd, BillingProd, ExternalProd, CaMooncake, CaFairfax, CaBlackforest
@geneva_account_name = ""
@geneva_account_namespace = ""
@geneva_logs_config_version = "2.0"
@infra_namespaces = []
@tenant_namespaces = []

# Use parser to parse the configmap toml file to a ruby structure
def parseConfigMap
  begin
    # Check to see if config map is created
    if (File.file?(@configMapMountPath))
      puts "config::configmap container-azm-ms-agentconfig found, parsing values for geneva logs config"
      parsedConfig = Tomlrb.load_file(@configMapMountPath, symbolize_keys: true)
      puts "config::Successfully parsed mounted config map"
      return parsedConfig
    else
      puts "config::configmap container-azm-ms-agentconfig  not mounted, using defaults"
      return nil
    end
  rescue => errorStr
    ConfigParseErrorLogger.logError("Exception while parsing config map for geneva logs config: #{errorStr}, using defaults, please check config map for errors")
    return nil
  end
end

# Use the ruby structure created after config parsing to set the right values to be used as environment variables
def populateSettingValuesFromConfigMap(parsedConfig)
  begin
    if !parsedConfig.nil? && !parsedConfig[:integrations].nil? && !parsedConfig[:integrations][:geneva_logs].nil?
      if !parsedConfig[:integrations][:geneva_logs][:enabled].nil?
        geneva_logs_integration = parsedConfig[:integrations][:geneva_logs][:enabled].to_s
        if !geneva_logs_integration.nil? && geneva_logs_integration.strip.casecmp("true") == 0
          @geneva_logs_integration = true
        else
          @geneva_logs_integration = false
        end
        if @geneva_logs_integration
          multi_tenancy = parsedConfig[:integrations][:geneva_logs][:multi_tenancy].to_s
          if !multi_tenancy.nil? && multi_tenancy.strip.casecmp("true") == 0
            @multi_tenancy = true
          end

          if @multi_tenancy
            # this is only applicable incase of multi-tenacy
            infra_namespaces = parsedConfig[:integrations][:geneva_logs][:infra_namespaces].to_s
            if !infra_namespaces.nil? && !infra_namespaces.empty? &&
               infra_namespaces.kind_of?(Array) && infra_namespaces.length > 0 &&
               infra_namespaces[0].kind_of?(String) # Checking only for the first element to be string because toml enforces the arrays to contain elements of same type
              @infra_namespaces = infra_namespaces.dup
            end
          end

          if !@multi_tenancy || (@multi_tenancy && !@infra_namespaces.empty?)
            geneva_account_environment = parsedConfig[:integrations][:geneva_logs][:environment].to_s
            geneva_account_namespace = parsedConfig[:integrations][:geneva_logs][:namespace].to_s
            geneva_account_name = parsedConfig[:integrations][:geneva_logs][:account].to_s
            geneva_logs_config_version = parsedConfig[:integrations][:geneva_logs][:configversion].to_s
            if isValidGenevaConfig(geneva_account_environment, geneva_account_namespace, geneva_account_name)
              @geneva_account_environment = geneva_account_environment
              @geneva_account_namespace = geneva_account_namespace
              @geneva_account_name = geneva_account_name
              if !geneva_logs_config_version.nil? && !geneva_logs_config_version.empty?
                @geneva_logs_config_version = geneva_logs_config_version
              else
                @geneva_logs_config_version = "2.0"
                puts "Since config version not specified so using default config version : #{@geneva_logs_config_version}"
              end
            else
              puts "config::geneva_logs::error: provided geneva logs config is not valid"
            end
          end

          if @multi_tenancy
            tenant_namespaces = parsedConfig[:integrations][:geneva_logs][:tenant_namespaces]
            if !tenant_namespaces.nil? && !tenant_namespaces.empty? &&
               tenant_namespaces.kind_of?(Array) && tenant_namespaces.length > 0 &&
               tenant_namespaces[0].kind_of?(String) # Checking only for the first element to be string because toml enforces the arrays to contain elements of same type
              @tenant_namespaces = tenant_namespaces.dup
            end
          end

          puts "Using config map value: GENEVA_LOGS_INTEGRATION=#{@geneva_logs_integration}"
          puts "Using config map value: GENEVA_LOGS_MULTI_TENANCY=#{@multi_tenancy}"

          puts "Using config map value: MONITORING_GCS_ENVIRONMENT=#{@geneva_account_environment}"
          puts "Using config map value: MONITORING_GCS_NAMESPACE=#{@geneva_account_namespace}"
          puts "Using config map value: MONITORING_GCS_ACCOUNT=#{@geneva_account_name}"
          puts "Using config map value: MONITORING_CONFIG_VERSION=#{@geneva_logs_config_version}"

          puts "Using config map value: GENEVA_LOGS_INFRA_NAMESPACES = #{@infra_namespaces}"
          puts "Using config map value: GENEVA_LOGS_TENANT_NAMESPACES = #{@tenant_namespaces}"
        end
      end
    end
  rescue => errorStr
    puts "config::geneva_logs::error:Exception while reading config settings for geneva logs setting - #{errorStr}, using defaults"
    @geneva_logs_integration = false
    @multi_tenancy = false
    @geneva_account_environment = ""
    @geneva_account_name = ""
    @geneva_account_namespace = ""
  end
end

def isValidGenevaConfig(environment, namespace, account)
  isValid = false
  begin
    if !environment.nil? && !environment.empty? &&
       !namespace.nil? && !namespace.empty? &&
       !account.nil? && !account.empty? &&
       GENEVA_SUPPORTED_ENVIRONMENTS.map(&:downcase).include?(environment.downcase)
      isValid = true
    end
  rescue => error
  end
  return isValid
end

def checkForTypeArray(arrayValue, arrayType)
  if (arrayValue.nil? || (arrayValue.kind_of?(Array) && ((arrayValue.length == 0) || (arrayValue.length > 0 && arrayValue[0].kind_of?(arrayType)))))
    return true
  else
    return false
  end
end

def get_command_windows(env_variable_name, env_variable_value)
  return "[System.Environment]::SetEnvironmentVariable(\"#{env_variable_name}\", \"#{env_variable_value}\", \"Process\")" + "\n" + "[System.Environment]::SetEnvironmentVariable(\"#{env_variable_name}\", \"#{env_variable_value}\", \"Machine\")" + "\n"
end

@configSchemaVersion = ENV["AZMON_AGENT_CFG_SCHEMA_VERSION"]
puts "****************Start Geneva logs Config Processing********************"
if !@configSchemaVersion.nil? && !@configSchemaVersion.empty? && @configSchemaVersion.strip.casecmp("v1") == 0 #note v1 is the only supported schema version , so hardcoding it
  configMapSettings = parseConfigMap
  if !configMapSettings.nil?
    populateSettingValuesFromConfigMap(configMapSettings)
  end
else
  if (File.file?(@configMapMountPath))
    ConfigParseErrorLogger.logError("config::integrations::unsupported/missing config schema version - '#{@configSchemaVersion}' , using defaults, please use supported schema version")
  end
  @geneva_logs_integration = false
  @multi_tenancy = false
  @geneva_account_environment = ""
  @geneva_account_name = ""
  @geneva_account_namespace = ""
end

# Write the settings to file, so that they can be set as environment variables
file = File.open("geneva_config_env_var", "w")

if !file.nil?
  file.write("export GENEVA_LOGS_INTEGRATION=#{@geneva_logs_integration}\n")
  file.write("export GENEVA_LOGS_MULTI_TENANCY=#{@multi_tenancy}\n")

  file.write("export MONITORING_GCS_ENVIRONMENT=#{@geneva_account_environment}\n")
  file.write("export MONITORING_GCS_NAMESPACE=#{@geneva_account_namespace}\n")
  file.write("export MONITORING_GCS_ACCOUNT=#{@geneva_account_name}\n")
  file.write("export MONITORING_CONFIG_VERSION=#{@geneva_logs_config_version}\n")

  file.write("export GENEVA_LOGS_INFRA_NAMESPACES=#{@infra_namespaces}\n")
  file.write("export GENEVA_LOGS_TENANT_NAMESPACES=#{@tenant_namespaces}\n")

  # Close file after writing all environment variables
  file.close
else
  puts "Exception while opening file for writing  geneva config environment variables"
  puts "****************End Config Processing********************"
end

if !@os_type.nil? && !@os_type.empty? && @os_type.strip.casecmp("windows") == 0
  # Write the settings to file, so that they can be set as environment variables
  file = File.open("setgenevaconfigenv.ps1", "w")

  if !file.nil?
    commands = get_command_windows("GENEVA_LOGS_INTEGRATION", @geneva_logs_integration)
    file.write(commands)
    commands = get_command_windows("GENEVA_LOGS_MULTI_TENANCY", @multi_tenancy)
    file.write(commands)

    commands = get_command_windows("MONITORING_GCS_ENVIRONMENT", @geneva_account_environment)
    file.write(commands)
    commands = get_command_windows("MONITORING_GCS_NAMESPACE", @geneva_account_namespace)
    file.write(commands)
    commands = get_command_windows("MONITORING_GCS_ACCOUNT", @geneva_account_name)
    file.write(commands)
    commands = get_command_windows("MONITORING_CONFIG_VERSION", @geneva_logs_config_version)
    file.write(commands)

    commands = get_command_windows("GENEVA_LOGS_INFRA_NAMESPACES", @infra_namespaces)
    file.write(commands)
    commands = get_command_windows("GENEVA_LOGS_TENANT_NAMESPACES", @tenant_namespaces)
    file.write(commands)
    # Close file after writing all environment variables
    file.close
    puts "****************End Config Processing********************"
  else
    puts "Exception while opening file for writing config environment variables for WINDOWS LOG"
    puts "****************End Config Processing********************"
  end
end
