#!/usr/local/bin/ruby
# frozen_string_literal: true

module Fluent
  class Container_Inventory_Input < Input
    Plugin.register_input("containerinventory", self)

    @@PluginName = "ContainerInventory"   

    def initialize
      super
      require "yajl/json_gem"
      require "time"      
      require_relative "ContainerInventoryState"
      require_relative "ApplicationInsightsUtility"
      require_relative "omslog"
      require_relative "CAdvisorMetricsAPIClient"
      require_relative "kubernetes_container_inventory"      
    end

    config_param :run_interval, :time, :default => 60
    config_param :tag, :string, :default => "oms.containerinsights.containerinventory"

    def configure(conf)
      super
    end

    def start
      if @run_interval
        @finished = false
        @condition = ConditionVariable.new
        @mutex = Mutex.new
        @thread = Thread.new(&method(:run_periodic))
        @@telemetryTimeTracker = DateTime.now.to_time.to_i
      end
    end

    def shutdown
      if @run_interval
        @mutex.synchronize {
          @finished = true
          @condition.signal
        }
        @thread.join
      end
    end   
  
    def enumerate
      currentTime = Time.now
      emitTime = currentTime.to_f
      batchTime = currentTime.utc.iso8601
      containerInventory = Array.new
      eventStream = MultiEventStream.new
      hostName = ""
      $log.info("in_container_inventory::enumerate : Begin processing @ #{Time.now.utc.iso8601}")
      begin
        containerRuntimeEnv = ENV["CONTAINER_RUNTIME"]
        $log.info("in_container_inventory::enumerate : container runtime : #{containerRuntimeEnv}")
        clusterCollectEnvironmentVar = ENV["AZMON_CLUSTER_COLLECT_ENV_VAR"]
        $log.info("in_container_inventory::enumerate : using cadvisor apis")                    
        containerIds = Array.new
        response = CAdvisorMetricsAPIClient.getPodsFromCAdvisor(winNode: nil)
        if !response.nil? && !response.body.nil?
            podList = JSON.parse(response.body)
            if !podList.nil? && !podList.empty? && podList.key?("items") && !podList["items"].nil? && !podList["items"].empty?
              podList["items"].each do |item|
                containerInventoryRecords = KubernetesContainerInventory.getContainerInventoryRecords(item, batchTime, clusterCollectEnvironmentVar)
                containerInventoryRecords.each do |containerRecord|
                  ContainerInventoryState.writeContainerState(containerRecord)
                  if hostName.empty? && !containerRecord["Computer"].empty?
                    hostName = containerRecord["Computer"]
                  end
                  containerIds.push containerRecord["InstanceID"]
                  containerInventory.push containerRecord
                end           
              end
            end  
        end                          
        # Update the state for deleted containers
        deletedContainers = ContainerInventoryState.getDeletedContainers(containerIds)
        if !deletedContainers.nil? && !deletedContainers.empty?
          deletedContainers.each do |deletedContainer|
            container = ContainerInventoryState.readContainerState(deletedContainer)
            if !container.nil?
              container.each { |k, v| container[k] = v }
              container["State"] = "Deleted"
              @@containerCGroupCache.delete(container["InstanceID"])
              containerInventory.push container
             end
           end
        end        
        containerInventory.each do |record|
          wrapper = {
            "DataType" => "CONTAINER_INVENTORY_BLOB",
            "IPName" => "ContainerInsights",
            "DataItems" => [record.each { |k, v| record[k] = v }],
          }
          eventStream.add(emitTime, wrapper) if wrapper
        end
        router.emit_stream(@tag, eventStream) if eventStream
        @@istestvar = ENV["ISTEST"]
        if (!@@istestvar.nil? && !@@istestvar.empty? && @@istestvar.casecmp("true") == 0 && eventStream.count > 0)
          $log.info("containerInventoryEmitStreamSuccess @ #{Time.now.utc.iso8601}")
        end
        $log.info("in_container_inventory::enumerate : Processing complete - emitted stream @ #{Time.now.utc.iso8601}")
        timeDifference = (DateTime.now.to_time.to_i - @@telemetryTimeTracker).abs
        timeDifferenceInMinutes = timeDifference / 60
        if (timeDifferenceInMinutes >= 5)
          @@telemetryTimeTracker = DateTime.now.to_time.to_i
          telemetryProperties = {}
          telemetryProperties["Computer"] = hostName
          telemetryProperties["ContainerCount"] = containerInventory.length
          ApplicationInsightsUtility.sendTelemetry(@@PluginName, telemetryProperties)
        end
      rescue => errorStr
        $log.warn("Exception in enumerate container inventory: #{errorStr}")
        $log.debug_backtrace(errorStr.backtrace)
        ApplicationInsightsUtility.sendExceptionTelemetry(errorStr)
      end
    end

    def run_periodic
      @mutex.lock
      done = @finished
      @nextTimeToRun = Time.now
      @waitTimeout = @run_interval
      until done
        @nextTimeToRun = @nextTimeToRun + @run_interval
        @now = Time.now
        if @nextTimeToRun <= @now
          @waitTimeout = 1
          @nextTimeToRun = @now
        else
          @waitTimeout = @nextTimeToRun - @now
        end
        @condition.wait(@mutex, @waitTimeout)
        done = @finished
        @mutex.unlock
        if !done
          begin
            $log.info("in_container_inventory::run_periodic.enumerate.start @ #{Time.now.utc.iso8601}")
            enumerate
            $log.info("in_container_inventory::run_periodic.enumerate.end @ #{Time.now.utc.iso8601}")
          rescue => errorStr
            $log.warn "in_container_inventory::run_periodic: Failed in enumerate container inventory: #{errorStr}"
            $log.debug_backtrace(errorStr.backtrace)
          end
        end
        @mutex.lock
      end
      @mutex.unlock
    end
  end # Container_Inventory_Input
end # module
