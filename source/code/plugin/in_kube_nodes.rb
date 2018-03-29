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
              eventStream = MultiEventStream.new
                #get node inventory 
                nodeInventory['items'].each do |items|
                    record = {}
                    record['CollectionTime'] = batchTime #This is the time that is mapped to become TimeGenerated
                    record['Computer'] = items['metadata']['name'] 
                    record['ClusterName'] = KubernetesApiClient.getClusterName
                    record['ClusterId'] = KubernetesApiClient.getClusterId  
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
                        #collect last transition to/from ready (no matter ready is true/false)
                        if condition['type'] == "Ready" && !condition['lastTransitionTime'].nil?
                          record['LastTransitionTimeReady'] = condition['lastTransitionTime']
                        end
                    end 
                    
                    record['KubeletVersion'] = items['status']['nodeInfo']['kubeletVersion']
                    record['KubeProxyVersion'] = items['status']['nodeInfo']['kubeProxyVersion']
                    eventStream.add(emitTime, record) if record
                end 
                router.emit_stream(@tag, eventStream) if eventStream
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
  
  