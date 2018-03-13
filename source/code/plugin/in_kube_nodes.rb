#!/usr/local/bin/ruby

module Fluent

    class Kube_nodeInventory_Input < Input
      Plugin.register_input('kubenodeinventory', self)
  
      def initialize
        super
        require 'yaml'
        require 'json'
  
        require_relative 'KubernetesApiClient'
        require_relative 'oms_common'
        require_relative 'omslog'
      end
  
      config_param :run_interval, :time, :default => '10m'
      config_param :tag, :string, :default => "oms.api.KubeNodeInventory.CollectionTime"
  
      def configure (conf)
        super
      end
  
      def start
        if KubernetesApiClient.isValidRunningNode && @run_interval
          @finished = false
          @condition = ConditionVariable.new
          @mutex = Mutex.new
          @thread = Thread.new(&method(:run_periodic))
        else
          enumerate
        end
      end
  
      def shutdown
        if KubernetesApiClient.isValidRunningNode && @run_interval
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
        if KubernetesApiClient.isValidRunningNode
          nodeInventory = JSON.parse(KubernetesApiClient.getKubeResourceInfo('nodes').body)
          begin
            if(!nodeInventory.empty?)

                #get allocatable limits per node as perf data
                #<TODO> Node capacity is different from node allocatable. Allocatable is what is avaialble for allocating pods.
                # In theory Capacity = Allocatable + kube-reserved + system-reserved + eviction-threshold
                # For more details refer to https://kubernetes.io/docs/tasks/administer-cluster/reserve-compute-resources/#node-allocatable 
                #metricDataItems = []
                #metricDataItems.concat(KubernetesApiClient.parseNodeLimits(nodeInventory, "allocatable", "cpu", "cpuAllocatableNanoCores"))
                #metricDataItems.concat(KubernetesApiClient.parseNodeLimits(nodeInventory, "allocatable", "memory", "memoryAllocatableBytes"))

                #metricDataItems.each do |record|
                #record['DataType'] = "LINUX_PERF_BLOB"
                #record['IPName'] = "LogManagement"
                #router.emit("oms.api.KubePerf", time, record) if record  
                #end  

                #get node inventory 
                nodeInventory['items'].each do |items|
                    record = {}
                    record['CollectionTime'] = batchTime #This is the time that is mapped to become TimeGenerated
                    record['Computer'] = items['metadata']['name']   
                    record['CreationTimeStamp'] = items['metadata']['creationTimestamp'] 
                    record['Labels'] = [items['metadata']['labels']]
                    record['Status'] = ""

                    # Refer to https://kubernetes.io/docs/concepts/architecture/nodes/#condition for possible node conditions.
                    # We check the status of each condition e.g. {"type": "OutOfDisk","status": "False"} . Based on this we 
                    # populate the KubeNodeInventory Status field. A possible value for this field could be "Ready OutofDisk"
                    # implying that the node is ready for hosting pods, however its out of disk.
                    
                    items['status']['conditions'].each do |condition|
                        if condition['status'] == "True"
                            record['Status'] += condition['type']
                        end 
                    end 
                    
                    record['KubeletVersion'] = items['status']['nodeInfo']['kubeletVersion']
                    record['KubeProxyVersion'] = items['status']['nodeInfo']['kubeProxyVersion']
                    router.emit(@tag, emitTime, record) if record
                end 
    
            end  
          rescue  => errorStr
            $log.warn "Failed to retrieve node inventory: #{errorStr}"
            $log.debug_backtrace(errorStr.backtrace)
          end       
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
  
    end # Kube_Node_Input
  
  end # module
  
  