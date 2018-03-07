#!/usr/local/bin/ruby

module Fluent
    
      class Kube_Perf_Input < Input
        Plugin.register_input('kubeperf', self)
    
        def initialize
          super
          require 'yaml'
          require 'json'
    
          require_relative 'CAdvisorMetricsAPIClient'
          require_relative 'KubernetesApiClient'
          require_relative 'oms_common'
          require_relative 'omslog'
        end
    
        config_param :run_interval, :time, :default => '10m'
        config_param :tag, :string, :default => "oms.api.KubePerf"
    
        def configure (conf)
          super
        end
    
        def start
          if @run_interval
            @finished = false
            @condition = ConditionVariable.new
            @mutex = Mutex.new
            @thread = Thread.new(&method(:run_periodic))
          else
            enumerate
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
    
        def enumerate()
          time = Time.now.to_f
          begin
              metricData = CAdvisorMetricsAPIClient.getMetrics()
              metricData.each do |record|
                      record['DataType'] = "LINUX_PERF_BLOB"
                      record['IPName'] = "LogManagement"
                      router.emit(@tag, time, record) if record    
              end 
              
              if KubernetesApiClient.isValidRunningNode
                #get resource requests & resource limits per container as perf data 
                podInventory = JSON.parse(KubernetesApiClient.getKubeResourceInfo('pods').body)
                if(!podInventory.empty?) 
                  containerMetricDataItems = []
                  hostName = (OMS::Common.get_hostname)
                  containerMetricDataItems.concat(KubernetesApiClient.getContainerResourceRequestsAndLimits(podInventory, "requests", hostName, "cpu","cpuRequestNanoCores"))
                  containerMetricDataItems.concat(KubernetesApiClient.getContainerResourceRequestsAndLimits(podInventory, "requests", hostName, "memory","memoryRequestBytes"))
                  containerMetricDataItems.concat(KubernetesApiClient.getContainerResourceRequestsAndLimits(podInventory, "limits", hostName, "cpu","cpuLimitNanoCores"))
                  containerMetricDataItems.concat(KubernetesApiClient.getContainerResourceRequestsAndLimits(podInventory, "limits", hostName, "memory","memoryLimitBytes"))
      
                  containerMetricDataItems.each do |record|
                    record['DataType'] = "LINUX_PERF_BLOB"
                    record['IPName'] = "LogManagement"
                    router.emit(@tag, time, record) if record  
                  end
                end

                #get allocatable limits per node as perf data
                #<TODO> Node capacity is different from node allocatable. Allocatable is what is avaialble for allocating pods.
                # In theory Capacity = Allocatable + kube-reserved + system-reserved + eviction-threshold
                # For more details refer to https://kubernetes.io/docs/tasks/administer-cluster/reserve-compute-resources/#node-allocatable
                nodeInventory = JSON.parse(KubernetesApiClient.getKubeResourceInfo('nodes').body)
                if(!nodeInventory.empty?)
                  nodeMetricDataItems = []
                  nodeMetricDataItems.concat(KubernetesApiClient.parseNodeLimits(nodeInventory, "allocatable", "cpu", "cpuAllocatableNanoCores"))
                  nodeMetricDataItems.concat(KubernetesApiClient.parseNodeLimits(nodeInventory, "allocatable", "memory", "memoryAllocatableBytes"))
  
                  nodeMetricDataItems.each do |record|
                    record['DataType'] = "LINUX_PERF_BLOB"
                    record['IPName'] = "LogManagement"
                    router.emit(@tag, time, record) if record 
                  end 
                end
              end  
                        
              rescue  => errorStr
              $log.warn "Failed to retrieve metric data: #{errorStr}"
              $log.debug_backtrace(errorStr.backtrace)
          end
        end
    
        def run_periodic
          @mutex.lock
          done = @finished
          until done
            @condition.wait(@mutex, @run_interval)
            done = @finished
            @mutex.unlock
            if !done
              enumerate
            end
            @mutex.lock
          end
          @mutex.unlock
        end
      end # Kube_Perf_Input
end # module
