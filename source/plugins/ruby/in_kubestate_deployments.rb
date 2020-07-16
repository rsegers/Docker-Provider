#!/usr/local/bin/ruby
# frozen_string_literal: true

module Fluent
    class Kube_Kubestate_Deployments_Input < Input
      Plugin.register_input("kubestatedeployments", self)
      @@istestvar = ENV["ISTEST"]
      # telemetry - To keep telemetry cost reasonable, we keep track of the max deployments over a period of 15m
      @@deploymentsCount = 0
      
      
  
      def initialize
        super
        require "yajl/json_gem"
        require "yajl"
        require "date"
        require "time"
  
        require_relative "KubernetesApiClient"
        require_relative "oms_common"
        require_relative "omslog"
        require_relative "ApplicationInsightsUtility"
        require_relative "constants"
  
        # roughly each deployment is 8k
        # 1000 deployments account to approximately 8MB
        @DEPLOYMENTS_CHUNK_SIZE = 1000
        @DEPLOYMENTS_API_GROUP = "apps"
        @@telemetryLastSentTime = DateTime.now.to_time.to_i
  
        
        @deploymentsRunningTotal = 0
  
        @NodeName = OMS::Common.get_hostname
        @ClusterId = KubernetesApiClient.getClusterId
        @ClusterName = KubernetesApiClient.getClusterName
      end
  
      config_param :run_interval, :time, :default => 60
      config_param :tag, :string, :default => Constants::INSIGHTSMETRICS_FLUENT_TAG
  
      def configure(conf)
        super
      end
  
      def start
        if @run_interval
          @finished = false
          @condition = ConditionVariable.new
          @mutex = Mutex.new
          @thread = Thread.new(&method(:run_periodic))
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
        begin
          deploymentList = nil
          currentTime = Time.now
          batchTime = currentTime.utc.iso8601
          
          #set the running total for this batch to 0
          @deploymentsRunningTotal = 0
  
          # Initializing continuation token to nil
          continuationToken = nil
          $log.info("in_kubestate_deployments::enumerate : Getting deployments from Kube API @ #{Time.now.utc.iso8601}")
          continuationToken, deploymentList = KubernetesApiClient.getResourcesAndContinuationToken("deployments?limit=#{@DEPLOYMENTS_CHUNK_SIZE}", api_group: @DEPLOYMENTS_API_GROUP)
          $log.info("in_kubestate_deployments::enumerate : Done getting deployments from Kube API @ #{Time.now.utc.iso8601}")
          if (!deploymentList.nil? && !deploymentList.empty? && deploymentList.key?("items") && !deploymentList["items"].nil? && !deploymentList["items"].empty?)
            parse_and_emit_records(deploymentList, batchTime)
          else
            $log.warn "in_kubestate_deployments::enumerate:Received empty deploymentList"
          end
  
          #If we receive a continuation token, make calls, process and flush data until we have processed all data
          while (!continuationToken.nil? && !continuationToken.empty?)
            continuationToken, deploymentList = KubernetesApiClient.getResourcesAndContinuationToken("deployments?limit=#{@DEPLOYMENTS_CHUNK_SIZE}&continue=#{continuationToken}", api_group: @DEPLOYMENTS_API_GROUP)
            if (!deploymentList.nil? && !deploymentList.empty? && deploymentList.key?("items") && !deploymentList["items"].nil? && !deploymentList["items"].empty?)
              parse_and_emit_records(deploymentList, batchTime)
            else
              $log.warn "in_kubestate_deployments::enumerate:Received empty deploymentList"
            end
          end
  
          # Setting this to nil so that we dont hold memory until GC kicks in
          deploymentList = nil
  
          $log.info("successfully emitted a total of #{@deploymentsRunningTotal} kube_state_deployment metrics")
          # Flush AppInsights telemetry once all the processing is done, only if the number of events flushed is greater than 0
          if (@deploymentsRunningTotal > @@deploymentsCount)
            @@deploymentsCount = @deploymentsRunningTotal
          end
          if (((DateTime.now.to_time.to_i - @@telemetryLastSentTime).abs)/60 ) >= Constants::KUBE_STATE_TELEMETRY_FLUSH_INTERVAL_IN_MINUTES
            #send telemetry
            $log.info "sending deployemt telemetry..."
            ApplicationInsightsUtility.sendMetricTelemetry("MaxDeploymentCount", @@deploymentsCount, {})
            #reset last sent value & time
            @@deploymentsCount = 0
            @@telemetryLastSentTime = DateTime.now.to_time.to_i
          end
        rescue => errorStr
          $log.warn "in_kubestate_deployments::enumerate:Failed in enumerate: #{errorStr}"
          ApplicationInsightsUtility.sendExceptionTelemetry("in_kubestate_deployments::enumerate:Failed in enumerate: #{errorStr}")
        end
      end # end enumerate
  
      def parse_and_emit_records(deployments, batchTime = Time.utc.iso8601)
        metricItems = []
        insightsMetricsEventStream = MultiEventStream.new
        begin
            metricInfo = deployments
            metricInfo["items"].each do |deployment|
                deploymentName = deployment["metadata"]["name"]
                deploymentNameSpace = deployment["metadata"]["namespace"]
                deploymentCreatedTime = ""
                if !deployment["metadata"]["creationTimestamp"].nil?
                    deploymentCreatedTime = deployment["metadata"]["creationTimestamp"]
                end
                deploymentStrategy = "RollingUpdate" #default when not specified as per spec
                if !deployment["spec"]["strategy"].nil? && !deployment["spec"]["strategy"]["type"].nil?
                    deploymentStrategy = deployment["spec"]["strategy"]["type"]
                end
                deploymentSpecReplicas = 1 #default is 1 as per k8s spec
                if !deployment["spec"]["replicas"].nil?
                    deploymentSpecReplicas = deployment["spec"]["replicas"]
                end
                deploymentStatusReadyReplicas = 0
                if !deployment["status"]["readyReplicas"].nil?
                    deploymentStatusReadyReplicas = deployment["status"]["readyReplicas"]
                end
                deploymentStatusUpToDateReplicas = 0
                if !deployment["status"]["updatedReplicas"].nil?
                    deploymentStatusUpToDateReplicas = deployment["status"]["updatedReplicas"]
                end
                deploymentStatusAvailableReplicas = 0
                if !deployment["status"]["availableReplicas"].nil?
                    deploymentStatusAvailableReplicas = deployment["status"]["availableReplicas"]
                end
                
                metricItem = {}
                metricItem["CollectionTime"] = batchTime
                metricItem["Computer"] = @NodeName
                metricItem["Name"] = Constants::INSIGHTSMETRICS_METRIC_NAME_KUBE_STATE_DEPLOYMENT_STATE
                metricItem["Value"] = deploymentStatusReadyReplicas
                metricItem["Origin"] = Constants::INSIGHTSMETRICS_TAGS_ORIGIN
                metricItem["Namespace"] = Constants::INSIGHTSMETRICS_TAGS_KUBESTATE_NAMESPACE

                metricTags = {}
                metricTags[Constants::INSIGHTSMETRICS_TAGS_CLUSTERID] = @ClusterId
                metricTags[Constants::INSIGHTSMETRICS_TAGS_CLUSTERNAME] = @ClusterName
                metricTags[Constants::INSIGHTSMETRICS_TAGS_KUBE_STATE_DEPLOYMENT_NAME] = deploymentName
                metricTags[Constants::INSIGHTSMETRICS_TAGS_K8SNAMESPACE] = deploymentNameSpace
                metricTags[Constants::INSIGHTSMETRICS_TAGS_KUBE_STATE_DEPLOYMENT_STRATEGY ] = deploymentStrategy
                metricTags[Constants::INSIGHTSMETRICS_TAGS_KUBE_STATE_CREATIONTIME] = deploymentCreatedTime
                metricTags[Constants::INSIGHTSMETRICS_TAGS_KUBE_STATE_DEPLOYMENT_SPEC_REPLICAS] = deploymentSpecReplicas
                metricTags[Constants::INSIGHTSMETRICS_TAGS_KUBE_STATE_DEPLOYMENT_STATUS_REPLICAS_UPDATED] = deploymentStatusUpToDateReplicas
                metricTags[Constants::INSIGHTSMETRICS_TAGS_KUBE_STATE_DEPLOYMENT_STATUS_REPLICAS_AVAILABLE] = deploymentStatusAvailableReplicas
                

                metricItem["Tags"] = metricTags

                metricItems.push(metricItem)
            end

            time = Time.now.to_f
            metricItems.each do |insightsMetricsRecord|
                wrapper = {
                  "DataType" => "INSIGHTS_METRICS_BLOB",
                  "IPName" => "ContainerInsights",
                  "DataItems" => [insightsMetricsRecord.each { |k, v| insightsMetricsRecord[k] = v }],
                }
                insightsMetricsEventStream.add(time, wrapper) if wrapper
            end
    
            router.emit_stream(Constants::INSIGHTSMETRICS_FLUENT_TAG, insightsMetricsEventStream) if insightsMetricsEventStream
            $log.info("successfully emitted #{metricItems.length()} kube_state_deployment metrics")
            @deploymentsRunningTotal = @deploymentsRunningTotal + metricItems.length()
            if (!@@istestvar.nil? && !@@istestvar.empty? && @@istestvar.casecmp("true") == 0 && insightsMetricsEventStream.count > 0)
                $log.info("kubestatedeploymentsInsightsMetricsEmitStreamSuccess @ #{Time.now.utc.iso8601}")
            end
        rescue => error
            $log.warn("in_kubestate_deployments::parse_and_emit_records failed: #{error} ")
            ApplicationInsightsUtility.sendExceptionTelemetry("in_kubestate_deployments::parse_and_emit_records failed: #{error}")
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
              $log.info("in_kubestate_deployments::run_periodic.enumerate.start @ #{Time.now.utc.iso8601}")
              enumerate
              $log.info("in_kubestate_deployments::run_periodic.enumerate.end @ #{Time.now.utc.iso8601}")
            rescue => errorStr
              $log.warn "in_kubestate_deployments::run_periodic: enumerate Failed to retrieve kube deployments: #{errorStr}"
              ApplicationInsightsUtility.sendExceptionTelemetry("in_kubestate_deployments::run_periodic: enumerate Failed to retrieve kube deployments: #{errorStr}")
            end
          end
          @mutex.lock
        end
        @mutex.unlock
      end
    end
end