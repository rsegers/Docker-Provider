#!/usr/local/bin/ruby


@os_type = ENV["OS_TYPE"]
require "tomlrb"

require_relative "ConfigParseErrorLogger"

@configMapMountPath = "/etc/config/settings/log-data-collection-settings"
@configVersion = ""
@configSchemaVersion = ""
# Setting default values which will be used in case they are not set in the configmap or if configmap doesnt exist
@collectStdoutLogs = true
@stdoutExcludeNamespaces = "kube-system,gatekeeper-system"
@stdoutIncludeSystemPods = ""
@collectStderrLogs = true
@stderrExcludeNamespaces = "kube-system,gatekeeper-system"
@stderrIncludeSystemPods = ""
@collectClusterEnvVariables = true
@logTailPath = "/var/log/containers/*.log"
@logExclusionRegexPattern = "(^((?!stdout|stderr).)*$)"
@excludePath = "*.csv2" #some invalid path
@enrichContainerLogs = false
@containerLogSchemaVersion = ""
@collectAllKubeEvents = false
@containerLogsRoute = "v2" # default for linux
@logEnableMultiline = "false"
@stacktraceLanguages = "go,java,python" #supported languages for multiline logs. java is also used for dotnet stacktraces
@logEnableKubernetesMetadata = false
@logKubernetesMetadataIncludeFields = "podlabels,podannotations,poduid,image,imageid,imagerepo,imagetag"
@annotationBasedLogFiltering = false
@allowed_system_namespaces = ['kube-system', 'gatekeeper-system', 'calico-system', 'azure-arc', 'kube-public', 'kube-node-lease']
@isAzMonMultiTenancyLogCollectionEnabled = false
@azMonMultiTenantNamespaces = []
@azMonMultiTenancyMaxStorageChunksUp = 500
@namespace_to_settings = {}

if !@os_type.nil? && !@os_type.empty? && @os_type.strip.casecmp("windows") == 0
  @containerLogsRoute = "v1" # default is v1 for windows until windows agent integrates windows ama
  # This path format is necessary for fluent-bit in windows
  @logTailPath = "C:\\var\\log\\containers\\*.log"
end

def generateAzMonMultiTenantNamespaceConfig
   templatefilePath = "/etc/opt/microsoft/docker-cimprov/fluent-bit-azmon-logs_tenant.conf"
   tail_storage_type = 'filesystem'
   mem_buf_limit = '10m'
   buffer_chunk_size = '1m'
   buffer_max_size = '5m'
   cluster_log_tail_exclude_path = '/var/log/exclude'
   throttle_rate = 1000
   throttle_window = 300
   throttle_interval = '1s'
   tenant_output_forward_worker_count = 10
   tenant_output_forward_retry_limit = 10
   tenant_output_forward_storage_total_limit_size = '2G'
   tenant_require_ack_response = false

   begin
    @azMonMultiTenantNamespaces.each do |namespace|
      puts "namespace onboarded to azmon multi-tenancy logs: #{namespace}"
      tenant_namespace = namespace
      tenant_settings = @namespace_to_settings[namespace]
      if tenant_settings.nil?
        puts "tenant settings not provided for namespace: #{namespace}, using defaults"
      else
        tail_storage_type = tenant_settings['tail_storage_type'] || tail_storage_type
        mem_buf_limit = tenant_settings['mem_buf_limit'] || mem_buf_limit
        buffer_chunk_size = tenant_settings['buffer_chunk_size'] || buffer_chunk_size
        buffer_max_size = tenant_settings['buffer_max_size'] || buffer_max_size
        throttle_rate = tenant_settings['throttle_rate'] || throttle_rate
        throttle_window = tenant_settings['throttle_window'] || throttle_window
        throttle_interval = tenant_settings['throttle_interval'] || throttle_interval
        tenant_output_forward_worker_count = tenant_settings['tenant_output_forward_worker_count'] || tenant_output_forward_worker_count
        tenant_output_forward_retry_limit = tenant_settings['tenant_output_forward_retry_limit'] || tenant_output_forward_retry_limit
        tenant_output_forward_storage_total_limit_size = tenant_settings['tenant_output_forward_storage_total_limit_size'] || tenant_output_forward_storage_total_limit_size
        tenant_require_ack_response = tenant_settings['tenant_require_ack_response'] || tenant_require_ack_response
      end
      templatefile = File.read(templatefilePath)
      templatefile = templatefile.gsub("<TENANT_NAMESPACE>", tenant_namespace)
      templatefile = templatefile.gsub("${AZMON_TENANT_TAIL_STORAGE_TYPE}", tail_storage_type)
      templatefile = templatefile.gsub("${AZMON_TENANT_TAIL_MEM_BUF_LIMIT}", mem_buf_limit)
      templatefile = templatefile.gsub("${AZMON_TENANT_TAIL_BUFFER_CHUNK_SIZE}", buffer_chunk_size)
      templatefile = templatefile.gsub("${AZMON_TENANT_TAIL_BUFFER_MAX_SIZE}", buffer_max_size)

      templatefile = templatefile.gsub("${AZMON_TENANT_THROTTLE_RATE}", throttle_rate.to_s)
      templatefile = templatefile.gsub("${AZMON_TENANT_THROTTLE_WINDOW}", throttle_window.to_s)
      templatefile = templatefile.gsub("${AZMON_TENANT_THROTTLE_INTERVAL}", throttle_interval)

      templatefile = templatefile.gsub("${AZMON_TENANT_OUTPUT_FORWARD_WORKERS_COUNT}", tenant_output_forward_worker_count.to_s)
      templatefile = templatefile.gsub("${AZMON_TENANT_OUTPUT_FORWARD_RETRY_LIMIT}", tenant_output_forward_retry_limit.to_s)
      templatefile = templatefile.gsub("${AZMON_TENANT_REQUIRE_ACK_RESPONSE}", tenant_require_ack_response)

      templatefile = templatefile.gsub("${AZMON_TENANT_OUTPUT_FORWARD_STORAGE_TOTAL_LIMIT_SIZE}", tenant_output_forward_storage_total_limit_size)

      tenant_file_path = "/etc/opt/microsoft/docker-cimprov/fluent-bit-azmon-logs_tenant_#{tenant_namespace}.conf"
      File.open(tenant_file_path, 'w') { |file| file.write(templatefile) }
    end
    # clear the template file
    File.open(templatefilePath, 'r+') do |file|
      file.truncate(0) # clear the file
    end
   rescue => exception
    puts "generateAzMonMultiTenantNamespaceConfig: Exception while generating tenant config files: #{exception}"
   end
end

# Use parser to parse the configmap toml file to a ruby structure
def parseConfigMap
  begin
    # Check to see if config map is created
    if (File.file?(@configMapMountPath))
      puts "config::configmap container-azm-ms-agentconfig for settings mounted, parsing values"
      parsedConfig = Tomlrb.load_file(@configMapMountPath, symbolize_keys: true)
      puts "config::Successfully parsed mounted config map"
      return parsedConfig
    else
      puts "config::configmap container-azm-ms-agentconfig for settings not mounted, using defaults"
      @excludePath = "*_kube-system_*.log"
      return nil
    end
  rescue => errorStr
    ConfigParseErrorLogger.logError("Exception while parsing config map for log collection/env variable settings: #{errorStr}, using defaults, please check config map for errors")
    @excludePath = "*_kube-system_*.log"
    return nil
  end
end

def isHighLogScaleMode?
  highLogScaleMode = false
  begin
    highscale = ENV["IS_HIGH_LOG_SCALE_MODE"]
    if !highscale.nil? && !highscale.empty? && highscale.to_s.downcase == "true"
      highLogScaleMode = true
    end
  rescue => errorStr
     ConfigParseErrorLogger.logError("Exception while reading IS_HIGH_LOG_SCALE_MODE env variable - #{errorStr}, using defaults, please check isHighLogScaleMode env variable for errors")
  end
  return highLogScaleMode
end

def isDaemonSet?
   isDaemonSet = false
   begin
     controllerType = ENV["CONTROLLER_TYPE"]
     if !controllerType.nil? && !controllerType.empty? && controllerType.to_s.downcase == "daemonset"
        isDaemonSet = true
     end
   rescue => errorStr
    ConfigParseErrorLogger.logError("Exception while reading CONTROLLER_TYPE env variable - #{errorStr}, using defaults, please check CONTROLLER_TYPE env variable for errors")
   end
   return isDaemonSet
end

# Use the ruby structure created after config parsing to set the right values to be used as environment variables
def populateSettingValuesFromConfigMap(parsedConfig)
  if !parsedConfig.nil? && !parsedConfig[:log_collection_settings].nil?
    #Get stdout log config settings
    begin
      if !parsedConfig[:log_collection_settings][:stdout].nil? && !parsedConfig[:log_collection_settings][:stdout][:enabled].nil?
        @collectStdoutLogs = parsedConfig[:log_collection_settings][:stdout][:enabled]
        puts "config::Using config map setting for stdout log collection"
        stdoutNamespaces = parsedConfig[:log_collection_settings][:stdout][:exclude_namespaces]

        stdoutSystemPods = Array.new
        if !parsedConfig[:log_collection_settings][:stdout][:collect_system_pod_logs].nil?
          stdoutSystemPods = parsedConfig[:log_collection_settings][:stdout][:collect_system_pod_logs]
        end

        #Clearing it, so that it can be overridden with the config map settings
        @stdoutExcludeNamespaces.clear
        if @collectStdoutLogs && !stdoutNamespaces.nil?
          if stdoutNamespaces.kind_of?(Array)
            # Checking only for the first element to be string because toml enforces the arrays to contain elements of same type
            if stdoutNamespaces.length > 0 && stdoutNamespaces[0].kind_of?(String)
              #Empty the array to use the values from configmap
              stdoutNamespaces.each do |namespace|
                if @stdoutExcludeNamespaces.empty?
                  # To not append , for the first element
                  @stdoutExcludeNamespaces.concat(namespace)
                else
                  @stdoutExcludeNamespaces.concat("," + namespace)
                end
              end
              puts "config::Using config map setting for stdout log collection to exclude namespace"
            end
          end
        end

        if @collectStdoutLogs && stdoutSystemPods.is_a?(Array) && !stdoutSystemPods.empty?
          # Using is_a? for type checking and directly checking if the array is not empty
          filtered_entries = stdoutSystemPods.each_with_object([]) do |pod, entries|
            namespace, controller = pod.split(':') # Split once and use the result
            if namespace && @allowed_system_namespaces.include?(namespace) && !@stdoutExcludeNamespaces.include?(namespace) && controller && !controller.empty?
              entries << pod
            else
              puts "config:: invalid entry for collect_system_pod_logs: #{pod}"
              unless @allowed_system_namespaces.include?(namespace)
                puts "config:: collect_system_pod_logs only works for system namespaces #{@allowed_system_namespaces}"
              end
              if @stdoutExcludeNamespaces.include?(namespace)
                puts "config:: please remove #{namespace} from exclude_namespaces to use collect_system_pod_logs"
              end
              if !controller || controller.empty?
                puts "config:: Please provide valid controller name. controller name is empty"
              end
            end
          end

          @stdoutIncludeSystemPods = filtered_entries.join(",")
          puts "config::Using config map setting for stdout log collection to include system pods" if filtered_entries.any?
        else
          puts "config::Stdout log collection is not enabled or stdoutSystemPods is not properly configured." unless @collectStdoutLogs
        end

      end
    rescue => errorStr
      ConfigParseErrorLogger.logError("Exception while reading config map settings for stdout log collection - #{errorStr}, using defaults, please check config map for errors")
    end

    #Get stderr log config settings
    begin
      if !parsedConfig[:log_collection_settings][:stderr].nil? && !parsedConfig[:log_collection_settings][:stderr][:enabled].nil?
        @collectStderrLogs = parsedConfig[:log_collection_settings][:stderr][:enabled]
        puts "config::Using config map setting for stderr log collection"
        stderrNamespaces = parsedConfig[:log_collection_settings][:stderr][:exclude_namespaces]

        stderrSystemPods = Array.new
        if !parsedConfig[:log_collection_settings][:stderr][:collect_system_pod_logs].nil?
          stderrSystemPods = parsedConfig[:log_collection_settings][:stderr][:collect_system_pod_logs]
        end

        stdoutNamespaces = Array.new
        #Clearing it, so that it can be overridden with the config map settings
        @stderrExcludeNamespaces.clear
        if @collectStderrLogs && !stderrNamespaces.nil?
          if stderrNamespaces.kind_of?(Array)
            if !@stdoutExcludeNamespaces.nil? && !@stdoutExcludeNamespaces.empty?
              stdoutNamespaces = @stdoutExcludeNamespaces.split(",")
            end
            # Checking only for the first element to be string because toml enforces the arrays to contain elements of same type
            if stderrNamespaces.length > 0 && stderrNamespaces[0].kind_of?(String)
              stderrNamespaces.each do |namespace|
                if @stderrExcludeNamespaces.empty?
                  # To not append , for the first element
                  @stderrExcludeNamespaces.concat(namespace)
                else
                  @stderrExcludeNamespaces.concat("," + namespace)
                end
                # Add this namespace to excludepath if both stdout & stderr are excluded for this namespace, to ensure are optimized and dont tail these files at all
                if stdoutNamespaces.include? namespace
                  @excludePath.concat("," + "*_" + namespace + "_*.log")
                end
              end
              puts "config::Using config map setting for stderr log collection to exclude namespace"
            end
          end
        end

        if @collectStderrLogs && stderrSystemPods.is_a?(Array) && !stderrSystemPods.empty?
          # Using is_a? for type checking and directly checking if the array is not empty
          filtered_entries = stderrSystemPods.each_with_object([]) do |pod, entries|
            namespace, controller = pod.split(':') # Split once and use the result
            if namespace && @allowed_system_namespaces.include?(namespace) && !@stderrExcludeNamespaces.include?(namespace) && controller && !controller.empty?
              entries << pod
            else
              puts "config:: invalid entry for collect_system_pod_logs: #{pod}"
              unless @allowed_system_namespaces.include?(namespace)
                puts "config:: collect_system_pod_logs only works for system namespaces #{@allowed_system_namespaces}"
              end
              if @stdoutExcludeNamespaces.include?(namespace)
                puts "config:: please remove #{namespace} from exclude_namespaces to use collect_system_pod_logs"
              end
              if !controller || controller.empty?
                puts "config:: Please provide valid controller name. controller name is empty"
              end
            end
          end

          @stderrIncludeSystemPods = filtered_entries.join(",")
          puts "config::Using config map setting for stderr log collection to include system pods" if filtered_entries.any?
        else
          puts "config::stderr log collection is not enabled or stderrSystemPods is not properly configured." unless @collectStderrLogs
        end

      end
    rescue => errorStr
      ConfigParseErrorLogger.logError("Exception while reading config map settings for stderr log collection - #{errorStr}, using defaults, please check config map for errors")
    end

    #Get environment variables log config settings
    begin
      if !parsedConfig[:log_collection_settings][:env_var].nil? && !parsedConfig[:log_collection_settings][:env_var][:enabled].nil?
        @collectClusterEnvVariables = parsedConfig[:log_collection_settings][:env_var][:enabled]
        puts "config::Using config map setting for cluster level environment variable collection"
      end
    rescue => errorStr
      ConfigParseErrorLogger.logError("Exception while reading config map settings for cluster level environment variable collection - #{errorStr}, using defaults, please check config map for errors")
    end

    #Get container log enrichment setting
    begin
      if !parsedConfig[:log_collection_settings][:enrich_container_logs].nil? && !parsedConfig[:log_collection_settings][:enrich_container_logs][:enabled].nil?
        @enrichContainerLogs = parsedConfig[:log_collection_settings][:enrich_container_logs][:enabled]
        puts "config::Using config map setting for cluster level container log enrichment"
      end
    rescue => errorStr
      ConfigParseErrorLogger.logError("Exception while reading config map settings for cluster level container log enrichment - #{errorStr}, using defaults, please check config map for errors")
    end

    #Get container log schema version setting
    begin
      if !parsedConfig[:log_collection_settings][:schema].nil? && !parsedConfig[:log_collection_settings][:schema][:containerlog_schema_version].nil?
        @containerLogSchemaVersion = parsedConfig[:log_collection_settings][:schema][:containerlog_schema_version]
        puts "config::Using config map setting for container log schema version"
      end
    rescue => errorStr
      ConfigParseErrorLogger.logError("Exception while reading config map settings for container log schema version - #{errorStr}, using defaults, please check config map for errors")
    end

    # Get multiline log enabling setting
    begin
      if !parsedConfig[:log_collection_settings][:enable_multiline_logs].nil? && !parsedConfig[:log_collection_settings][:enable_multiline_logs][:enabled].nil?
        @logEnableMultiline = parsedConfig[:log_collection_settings][:enable_multiline_logs][:enabled]
        puts "config::Using config map setting for multiline logging"

        multilineLanguages = parsedConfig[:log_collection_settings][:enable_multiline_logs][:stacktrace_languages]
        if !multilineLanguages.nil?
          if multilineLanguages.kind_of?(Array)
            # Checking only for the first element to be string because toml enforces the arrays to contain elements of same type
            # update stacktraceLanguages only if customer explicity overrode via configmap
            #Empty the array to use the values from configmap
            @stacktraceLanguages.clear
            if multilineLanguages.length > 0 && multilineLanguages[0].kind_of?(String)
              invalid_lang = multilineLanguages.any? { |lang| !["java", "python", "go", "dotnet"].include?(lang.downcase) }
              if invalid_lang
                puts "config::WARN: stacktrace languages contains invalid languages. Disabling multiline stacktrace logging"
              else
                multilineLanguages = multilineLanguages.map(&:downcase)
                # the java multiline parser also captures dotnet
                if multilineLanguages.include?("dotnet")
                  multilineLanguages.delete("dotnet")
                  multilineLanguages << "java" unless multilineLanguages.include?("java")
                end
                @stacktraceLanguages = multilineLanguages.join(",")
                puts "config::Using config map setting for multiline languages"
              end
            else
              puts "config::WARN: stacktrace languages is not an array of strings. Disabling multiline stacktrace logging"
            end
          end
        end
      end
    rescue => errorStr
      ConfigParseErrorLogger.logError("Exception while reading config map settings for enabling multiline logs - #{errorStr}, using defaults, please check config map for errors")
    end

    #Get kube events enrichment setting
    begin
      if !parsedConfig[:log_collection_settings][:collect_all_kube_events].nil? && !parsedConfig[:log_collection_settings][:collect_all_kube_events][:enabled].nil?
        @collectAllKubeEvents = parsedConfig[:log_collection_settings][:collect_all_kube_events][:enabled]
        puts "config::Using config map setting for kube event collection"
      end
    rescue => errorStr
      ConfigParseErrorLogger.logError("Exception while reading config map settings for kube event collection - #{errorStr}, using defaults, please check config map for errors")
    end

    #Get container logs route setting
    begin
      if !parsedConfig[:log_collection_settings][:route_container_logs].nil? && !parsedConfig[:log_collection_settings][:route_container_logs][:version].nil?
        if !parsedConfig[:log_collection_settings][:route_container_logs][:version].empty?
          @containerLogsRoute = parsedConfig[:log_collection_settings][:route_container_logs][:version]
          puts "config::Using config map setting for container logs route: #{@containerLogsRoute}"
        else
          puts "config::Ignoring config map settings and using default value since provided container logs route value is empty"
        end
      end
    rescue => errorStr
      ConfigParseErrorLogger.logError("Exception while reading config map settings for container logs route - #{errorStr}, using defaults, please check config map for errors")
    end

    #Get Kubernetes Metadata setting
    begin
      if !parsedConfig[:log_collection_settings][:metadata_collection].nil? && !parsedConfig[:log_collection_settings][:metadata_collection][:enabled].nil?
        puts "config::INFO: Using config map setting for kubernetes metadata"
        @logEnableKubernetesMetadata = parsedConfig[:log_collection_settings][:metadata_collection][:enabled]
        if !parsedConfig[:log_collection_settings][:metadata_collection][:include_fields].nil?
          puts "config::INFO: Using config map setting for kubernetes metadata include fields"
          include_fields = parsedConfig[:log_collection_settings][:metadata_collection][:include_fields]
          if include_fields.empty?
            puts "config::WARN: Include fields specified for Kubernetes metadata is empty, disabling Kubernetes metadata"
            @logEnableKubernetesMetadata = false
          elsif include_fields.kind_of?(Array)
            include_fields.map!(&:downcase)
            predefined_fields = @logKubernetesMetadataIncludeFields.downcase.split(',')
            any_field_match = include_fields.any? { |field| predefined_fields.include?(field) }
            if any_field_match
              @logKubernetesMetadataIncludeFields = include_fields.join(",")
            else
              puts "config:: WARN: Include fields specified for Kubernetes metadata does not match any predefined fields, disabling Kubernetes metadata"
              @logEnableKubernetesMetadata = false
            end
          end
        end
      end
    rescue => errorStr
      ConfigParseErrorLogger.logError("config::error: Exception while reading config map settings for kubernetes metadata - #{errorStr}, please check config map for errors")
    end

    #Get annotation based log filtering setting
    begin
      if !parsedConfig[:log_collection_settings][:filter_using_annotations].nil? && !parsedConfig[:log_collection_settings][:filter_using_annotations][:enabled].nil?
        puts "config::INFO: Using config map setting for annotation based log filtering"
        @annotationBasedLogFiltering = parsedConfig[:log_collection_settings][:filter_using_annotations][:enabled]
      end
    rescue => errorStr
      ConfigParseErrorLogger.logError("config::error: Exception while reading config map settings for annotation based log filtering - #{errorStr}, please check config map for errors")
    end

    #Get Multi-tenancy log collection settings
    begin
      if isDaemonSet? # high log scale mode only applicable for daemonset
        if !parsedConfig[:log_collection_settings][:multi_tenancy].nil? && !parsedConfig[:log_collection_settings][:multi_tenancy][:enabled].nil?
          multi_tenancy_enabled = parsedConfig[:log_collection_settings][:multi_tenancy][:enabled]
          if multi_tenancy_enabled && isHighLogScaleMode? # Multi-tenancy log collection supported only in high log scale mode
            @isAzMonMultiTenancyLogCollectionEnabled = multi_tenancy_enabled
          else
            ConfigParseErrorLogger.logError("config::error: High Log Scale Mode MUST be enabled for Multi-tenancy log collection and ignoring the multi_tenancy config map setting")
          end
          if @isAzMonMultiTenancyLogCollectionEnabled
            namespaces = parsedConfig[:log_collection_settings][:multi_tenancy][:namespaces]
            puts "config::INFO:multi_tenancy namespaces provided in the configmap: #{namespaces}"
            if !namespaces.nil? && !namespaces.empty? &&
              namespaces.kind_of?(Array) && namespaces.length > 0 &&
              namespaces[0].kind_of?(String) # Checking only for the first element to be string because toml enforces the arrays to contain elements of same type
              namespaces.each do |namespace|
                namespace = namespace.strip.downcase
                if !@azMonMultiTenantNamespaces.include?(namespace)
                   @azMonMultiTenantNamespaces.push(namespace)
                end
              end
            end
            # max storage chunks
            storage_max_chunks_up = parsedConfig[:log_collection_settings][:multi_tenancy][:storage_max_chunks_up]
            if !storage_max_chunks_up.nil? && !storage_max_chunks_up.empty? && storage_max_chunks_up.to_i > 0
               @azMonMultiTenancyMaxStorageChunksUp = storage_max_chunks_up.to_i
            end
            # namepsace to settings
            namespace_settings = parsedConfig[:log_collection_settings][:multi_tenancy][:namespace_settings]
            if  @azMonMultiTenantNamespaces.length > 0 && !namespace_settings.nil? && !namespace_settings.empty? &&
              namespace_settings.kind_of?(Array) && namespace_settings.length > 0 &&
              namespace_settings[0].kind_of?(String) # Checking only for the first element to be string because toml enforces the arrays to contain elements of same type
              namespace_settings.each do |entry|
                namespace, settings_str = entry.split(':')
                settings = settings_str.split(';').map { |s| s.split('=') }.to_h
                namespace = namespace.strip.downcase
                if @namespace_to_settings.key?(namespace)
                  puts "config::WARN: Duplicate namespace settings found for namespace: #{namespace}, using the previous settings"
                else
                   @namespace_to_settings[namespace] = settings
                end
              end
              generateAzMonMultiTenantNamespaceConfig()
            end
          end
          puts "config::INFO: Using config map setting enabled: #{@isAzMonMultiTenancyLogCollectionEnabled} and namespaces: #{@azMonMultiTenantNamespaces} for Multi-tenancy log collection"
        end
      end
    rescue => errorStr
      ConfigParseErrorLogger.logError("config::error: Exception while reading config map settings for Multi-tenancy log collection - #{errorStr}, please check config map for errors")
    end
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
  @excludePath = "*_kube-system_*.log"
end

# Write the settings to file, so that they can be set as environment variables
file = File.open("config_env_var", "w")

if !file.nil?
  # This will be used in fluent-bit.conf file to filter out logs
  if (!@collectStdoutLogs && !@collectStderrLogs)
    #Stop log tailing completely
    @logTailPath = "/opt/nolog*.log"
    @logExclusionRegexPattern = "stdout|stderr"
  elsif !@collectStdoutLogs
    @logExclusionRegexPattern = "stdout"
  elsif !@collectStderrLogs
    @logExclusionRegexPattern = "stderr"
  end
  file.write("export AZMON_COLLECT_STDOUT_LOGS=#{@collectStdoutLogs}\n")
  file.write("export AZMON_LOG_TAIL_PATH=#{@logTailPath}\n")
  logTailPathDir = File.dirname(@logTailPath)
  file.write("export AZMON_LOG_TAIL_PATH_DIR=#{logTailPathDir}\n")
  file.write("export AZMON_LOG_EXCLUSION_REGEX_PATTERN=\"#{@logExclusionRegexPattern}\"\n")
  file.write("export AZMON_STDOUT_EXCLUDED_NAMESPACES=#{@stdoutExcludeNamespaces}\n")
  file.write("export AZMON_STDOUT_INCLUDED_SYSTEM_PODS=#{@stdoutIncludeSystemPods}\n")
  file.write("export AZMON_COLLECT_STDERR_LOGS=#{@collectStderrLogs}\n")
  file.write("export AZMON_STDERR_EXCLUDED_NAMESPACES=#{@stderrExcludeNamespaces}\n")
  file.write("export AZMON_STDERR_INCLUDED_SYSTEM_PODS=#{@stderrIncludeSystemPods}\n")
  file.write("export AZMON_CLUSTER_COLLECT_ENV_VAR=#{@collectClusterEnvVariables}\n")
  file.write("export AZMON_CLUSTER_LOG_TAIL_EXCLUDE_PATH=#{@excludePath}\n")
  file.write("export AZMON_CLUSTER_CONTAINER_LOG_ENRICH=#{@enrichContainerLogs}\n")
  file.write("export AZMON_CLUSTER_COLLECT_ALL_KUBE_EVENTS=#{@collectAllKubeEvents}\n")
  file.write("export AZMON_CONTAINER_LOGS_ROUTE=#{@containerLogsRoute}\n")
  file.write("export AZMON_CONTAINER_LOG_SCHEMA_VERSION=#{@containerLogSchemaVersion}\n")
  file.write("export AZMON_MULTILINE_ENABLED=#{@logEnableMultiline}\n")
  file.write("export AZMON_MULTILINE_LANGUAGES=#{@stacktraceLanguages}\n")
  file.write("export AZMON_KUBERNETES_METADATA_ENABLED=#{@logEnableKubernetesMetadata}\n")
  file.write("export AZMON_KUBERNETES_METADATA_INCLUDES_FIELDS=#{@logKubernetesMetadataIncludeFields}\n")
  file.write("export AZMON_ANNOTATION_BASED_LOG_FILTERING=#{@annotationBasedLogFiltering}\n")
  if @isAzMonMultiTenancyLogCollectionEnabled
    file.write("export AZMON_MULTI_TENANCY_LOG_COLLECTION=#{@isAzMonMultiTenancyLogCollectionEnabled}\n")
    azMonMultiTenantNamespacesString = @azMonMultiTenantNamespaces.join(",")
    file.write("export AZMON_MULTI_TENANCY_NAMESPACES=#{azMonMultiTenantNamespacesString}\n")
    file.write("export AZMON_MULTI_TENANCY_STORAGE_MAX_CHUNKS_UP=#{@azMonMultiTenancyMaxStorageChunksUp}\n")
  end

  # Close file after writing all environment variables
  file.close
  puts "Both stdout & stderr log collection are turned off for namespaces: '#{@excludePath}' "
  puts "****************End Config Processing********************"
else
  puts "Exception while opening file for writing config environment variables"
  puts "****************End Config Processing********************"
end

=begin
This section generates the file that will set the environment variables for windows. This script will be called by the main.ps1 script
which is the ENTRYPOINT script for the windows aks log container
=end

def get_command_windows(env_variable_name, env_variable_value)
  return "#{env_variable_name}=#{env_variable_value}\n"
end

if !@os_type.nil? && !@os_type.empty? && @os_type.strip.casecmp("windows") == 0
  # Write the settings to file, so that they can be set as environment variables
  file = File.open("setenv.txt", "w")

  if !file.nil?
    # This will be used in fluent-bit.conf file to filter out logs
    if (!@collectStdoutLogs && !@collectStderrLogs)
      #Stop log tailing completely
      @logTailPath = "C:\\opt\\nolog*.log"
      @logExclusionRegexPattern = "stdout|stderr"
    elsif !@collectStdoutLogs
      @logExclusionRegexPattern = "stdout"
    elsif !@collectStderrLogs
      @logExclusionRegexPattern = "stderr"
    end
    commands = get_command_windows("AZMON_COLLECT_STDOUT_LOGS", @collectStdoutLogs)
    file.write(commands)
    commands = get_command_windows("AZMON_LOG_TAIL_PATH", @logTailPath)
    file.write(commands)
    logTailPathDir = File.dirname(@logTailPath)
    commands = get_command_windows("AZMON_LOG_TAIL_PATH_DIR", logTailPathDir)
    file.write(commands)
    commands = get_command_windows("AZMON_LOG_EXCLUSION_REGEX_PATTERN", @logExclusionRegexPattern)
    file.write(commands)
    commands = get_command_windows("AZMON_STDOUT_EXCLUDED_NAMESPACES", @stdoutExcludeNamespaces)
    file.write(commands)
    commands = get_command_windows("AZMON_STDOUT_INCLUDED_SYSTEM_PODS", @stdoutIncludeSystemPods)
    file.write(commands)
    commands = get_command_windows("AZMON_COLLECT_STDERR_LOGS", @collectStderrLogs)
    file.write(commands)
    commands = get_command_windows("AZMON_STDERR_EXCLUDED_NAMESPACES", @stderrExcludeNamespaces)
    file.write(commands)
    commands = get_command_windows("AZMON_STDERR_INCLUDED_SYSTEM_PODS", @stderrIncludeSystemPods)
    file.write(commands)
    commands = get_command_windows("AZMON_CLUSTER_COLLECT_ENV_VAR", @collectClusterEnvVariables)
    file.write(commands)
    commands = get_command_windows("AZMON_CLUSTER_LOG_TAIL_EXCLUDE_PATH", @excludePath)
    file.write(commands)
    commands = get_command_windows("AZMON_CLUSTER_CONTAINER_LOG_ENRICH", @enrichContainerLogs)
    file.write(commands)
    commands = get_command_windows("AZMON_CLUSTER_COLLECT_ALL_KUBE_EVENTS", @collectAllKubeEvents)
    file.write(commands)
    commands = get_command_windows("AZMON_CONTAINER_LOGS_ROUTE", @containerLogsRoute)
    file.write(commands)
    commands = get_command_windows("AZMON_CONTAINER_LOG_SCHEMA_VERSION", @containerLogSchemaVersion)
    file.write(commands)
    commands = get_command_windows("AZMON_MULTILINE_ENABLED", @logEnableMultiline)
    file.write(commands)
    commands = get_command_windows("AZMON_MULTILINE_LANGUAGES", @stacktraceLanguages)
    file.write(commands)
    commands = get_command_windows("AZMON_KUBERNETES_METADATA_ENABLED", @logEnableKubernetesMetadata)
    file.write(commands)
    commands = get_command_windows("AZMON_KUBERNETES_METADATA_INCLUDES_FIELDS", @logKubernetesMetadataIncludeFields)
    file.write(commands)
    commands = get_command_windows("AZMON_ANNOTATION_BASED_LOG_FILTERING", @annotationBasedLogFiltering)
    file.write(commands)
    if @isAzMonMultiTenancyLogCollectionEnabled
      commands = get_command_windows("AZMON_MULTI_TENANCY_LOG_COLLECTION", @isAzMonMultiTenancyLogCollectionEnabled)
      file.write(commands)
      azMonMultiTenantNamespacesString = @azMonMultiTenantNamespaces.join(",")
      commands = get_command_windows("AZMON_MULTI_TENANCY_NAMESPACES", azMonMultiTenantNamespacesString)
      file.write(commands)
      commands = get_command_windows("AZMON_MULTI_TENANCY_STORAGE_MAX_CHUNKS_UP", @azMonMultiTenancyMaxStorageChunksUp)
      file.write(commands)
    end
    # Close file after writing all environment variables
    file.close
    puts "Both stdout & stderr log collection are turned off for namespaces: '#{@excludePath}' "
    puts "****************End Config Processing********************"
  else
    puts "Exception while opening file for writing config environment variables for WINDOWS LOG"
    puts "****************End Config Processing********************"
  end
end
