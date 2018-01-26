#!/usr/local/bin/ruby

module Fluent
    
      class Kube_Services_Input < Input
        Plugin.register_input('kubeservices', self)
    
        def initialize
          super
          require 'yaml'
          require 'json'
    
          require_relative 'KubernetesApiClient'
          require_relative 'oms_common'
          require_relative 'omslog'
        end
    
        config_param :run_interval, :time, :default => '1m'
        config_param :tag, :string, :default => "oms.api.KubeServices"
    
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
            time = Time.now.to_f
            if KubernetesApiClient.isValidRunningNode
              serviceList = JSON.parse(KubernetesApiClient.getKubeResourceInfo('services').body)
              begin
                if(!serviceList.empty?)
                  serviceList['items'].each do |items|
                    record = {}
                    record['ServiceName'] = items['metadata']['name']
                    record['Namespace'] = items['metadata']['namespace']
                    record['SelectorLabels'] = [items['spec']['selector']]
                    record['ClusterName'] = KubernetesApiClient.getClusterName
                    record['ClusterIP'] = items['spec']['clusterIP']
                    record['ServiceType'] = items['spec']['type']
                    #<TODO> : Add ports and status fields
                    router.emit(@tag, time, record) if record   
                  end
                end  
              rescue  => errorStr
                $log.warn line.dump, error: errorStr.to_s
                $log.debug_backtrace(e.backtrace)
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
    
      end # Kube_Services_Input
    
    end # module
    
    