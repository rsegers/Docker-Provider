#!/usr/local/bin/ruby

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
@geneva_account_namespace_name = ""
@geneva_logs_config_version = "2.0"
@infra_namespaces_prefix = ""
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
            infra_namespaces_prefix = parsedConfig[:integrations][:geneva_logs][:infra_namespaces_prefix].to_s
            if !infra_namespaces_prefix.nil? && !infra_namespaces_prefix.empty?
              @infra_namespaces_prefix = infra_namespaces_prefix
            end
          end

          if !@multi_tenancy || (@multi_tenancy && !@infra_namespaces_prefix.empty?)
            geneva_account_environment = parsedConfig[:integrations][:geneva_logs][:environment].to_s
            geneva_account_namespace = parsedConfig[:integrations][:geneva_logs][:namespace].to_s
            geneva_account_name = parsedConfig[:integrations][:geneva_logs][:account].to_s
            geneva_logs_config_version = parsedConfig[:integrations][:geneva_logs][:configversion].to_s
            if isValidGenevaConfig(geneva_account_environment, geneva_account_namespace, geneva_account_name, geneva_logs_config_version)
              @geneva_account_environment = geneva_account_environment
              @geneva_account_namespace = geneva_account_namespace
              @geneva_account_name = geneva_account_name
              if !geneva_logs_config_version.nil? && !geneva_logs_config_version.empty?
                @geneva_logs_config_version = geneva_logs_config_version
              end
            end
          end

          if @multi_tenancy
            tenant_namespaces = parsedConfig[:integrations][:geneva_logs][:tenant_namespaces]
            if isValidTenantNamespaces(isValidTenantNamespaces)
              @tenant_namespaces = tenant_namespaces
            end
          end
        end
      end
    end
  rescue => errorStr
    puts "config::npm::error:Exception while reading config settings for geneva logs setting - #{errorStr}, using defaults"
    @geneva_logs_integration = false
    @multi_tenancy = false
    @geneva_account_environment = ""
    @geneva_account_name = ""
    @geneva_account_namespace = ""
  end
end

def isValidGenevaConfig(environment, namespace, account, configVersion)
  isValid = true
  begin
    if !GENEVA_SUPPORTED_ENVIRONMENTS.include?(environment) || namespace.empty? || account.empty?
      isValid = false
    end
  rescue => error
  end
  return isValid
end

def isValidTenantNamespaces(tenant_namespaces)
  begin
    if tenant_namespaces && !tenant_namespaces.nil? && checkForTypeArray(monitorKubernetesPodsNamespaces, String)
      return true
    end
  rescue => errorStr
  end
  return false
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
  @geneva_account_namespace_name = ""
end

# Write the settings to file, so that they can be set as environment variables
file = File.open("geneva_config_env_var", "w")

if !file.nil?
  file.write("export GENEVA_LOGS_INTEGRATION=#{@geneva_logs_integration}\n")
  file.write("export GENEVA_LOGS_MULTI_TENANCY=#{@multi_tenancy}\n")

  file.write("export MONITORING_GCS_ENVIRONMENT=#{@geneva_account_environment}\n")
  file.write("export MONITORING_GCS_NAMESPACE=#{@geneva_account_namespace_name}\n")
  file.write("export MONITORING_GCS_ACCOUNT=#{@geneva_account_name}\n")
  file.write("export MONITORING_CONFIG_VERSION=#{@geneva_logs_config_version}\n")

  file.write("export GENEVA_LOGS_INFRA_NAMESPACES_PREFIX=#{@infra_namespaces_prefix}\n")
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
    commands = get_command_windows("MONITORING_GCS_NAMESPACE", @geneva_account_namespace_name)
    file.write(commands)
    commands = get_command_windows("MONITORING_GCS_ACCOUNT", @geneva_account_name)
    file.write(commands)
    commands = get_command_windows("MONITORING_CONFIG_VERSION", @geneva_logs_config_version)
    file.write(commands)

    commands = get_command_windows("GENEVA_LOGS_INFRA_NAMESPACES_PREFIX", @infra_namespaces_prefix)
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
