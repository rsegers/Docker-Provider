#!/usr/local/bin/ruby
# frozen_string_literal: true
require "fluent/plugin/input"

module Fluent::Plugin
  class CAdvisor_Perf_Input < Input
    Fluent::Plugin.register_input("cadvisor_perf", self)
    @@isWindows = false
    @@os_type = ENV["OS_TYPE"]
    if !@@os_type.nil? && !@@os_type.empty? && @@os_type.strip.casecmp("windows") == 0
      @@isWindows = true
    end
    @@totalPerfCount = 0

    def initialize
      super
      require "yaml"
      require "json"
      require "time"

      require_relative "CAdvisorMetricsAPIClient"
      require_relative "oms_common"
      require_relative "omslog"
      require_relative "constants"
      require_relative "extension_utils"
      @namespaces = []
      @namespaceFilteringMode = "off"
      @agentConfigRefreshTracker = DateTime.now.to_time.to_i
      @cadvisorPerfTelemetryTicker = DateTime.now.to_time.to_i
    end

    config_param :run_interval, :time, :default => 60
    config_param :tag, :string, :default => "oneagent.containerInsights.LINUX_PERF_BLOB"
    config_param :mdmtag, :string, :default => "mdm.cadvisorperf"
    config_param :insightsmetricstag, :string, :default => "oneagent.containerInsights.INSIGHTS_METRICS_BLOB"

    def configure(conf)
      super
    end

    def start
      if @run_interval
        super
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
        super # This super must be at the end of shutdown method
      end
    end

    def enumerate()
      currentTime = Time.now
      time = Fluent::Engine.now
      batchTime = currentTime.utc.iso8601
      @@istestvar = ENV["ISTEST"]
      telemetryFlush = false
      begin
        eventStream = Fluent::MultiEventStream.new
        insightsMetricsEventStream = Fluent::MultiEventStream.new

        if ExtensionUtils.isAADMSIAuthMode() && !@@isWindows.nil? && @@isWindows == false
          $log.info("in_cadvisor_perf::enumerate: AAD AUTH MSI MODE")
          @tag, isFromCache = KubernetesApiClient.getOutputStreamIdAndSource(Constants::PERF_DATA_TYPE, @tag, @agentConfigRefreshTracker)
          if !isFromCache
            @agentConfigRefreshTracker = DateTime.now.to_time.to_i
          end
          @insightsmetricstag, _ = KubernetesApiClient.getOutputStreamIdAndSource(Constants::INSIGHTS_METRICS_DATA_TYPE, @insightsmetricstag, @agentConfigRefreshTracker)
          if !KubernetesApiClient.isDCRStreamIdTag(@tag)
            $log.warn("in_cadvisor_perf::enumerate: skipping Microsoft-Perf stream since its opted-out @ #{Time.now.utc.iso8601}")
          end
          if !KubernetesApiClient.isDCRStreamIdTag(@insightsmetricstag)
            $log.warn("in_cadvisor_perf::enumerate: skipping Microsoft-InsightsMetrics stream since its opted-out @ #{Time.now.utc.iso8601}")
          end
          if ExtensionUtils.isDataCollectionSettingsConfigured()
            @run_interval = ExtensionUtils.getDataCollectionIntervalSeconds()
            $log.info("in_cadvisor_perf::enumerate: using data collection interval(seconds): #{@run_interval} @ #{Time.now.utc.iso8601}")
            @namespaces = ExtensionUtils.getNamespacesForDataCollection()
            $log.info("in_cadvisor_perf::enumerate: using data collection namespaces: #{@namespaces} @ #{Time.now.utc.iso8601}")
            @namespaceFilteringMode = ExtensionUtils.getNamespaceFilteringModeForDataCollection()
            $log.info("in_cadvisor_perf::enumerate: using data collection filtering mode for namespaces: #{@namespaceFilteringMode} @ #{Time.now.utc.iso8601}")
          end
        end

        metricData = CAdvisorMetricsAPIClient.getMetrics(winNode: nil, namespaceFilteringMode: @namespaceFilteringMode, namespaces: @namespaces, metricTime: batchTime)
        metricData.each do |record|
          eventStream.add(time, record) if record
        end

        router.emit_stream(@tag, eventStream) if !@tag.nil? && !@tag.empty? && eventStream
        router.emit_stream(@mdmtag, eventStream) if eventStream

        if (!@@istestvar.nil? && !@@istestvar.empty? && @@istestvar.casecmp("true") == 0 && eventStream.count > 0)
          $log.info("cAdvisorPerfEmitStreamSuccess @ #{Time.now.utc.iso8601}")
        end

        if metricData.length > 0
          @@totalPerfCount += metricData.length
        end

        #send the number of CAdvisor Perf records sent metrics telemetry
        timeDifference = (DateTime.now.to_time.to_i - @cadvisorPerfTelemetryTicker).abs
        timeDifferenceInMinutes = timeDifference / 60
        if (timeDifferenceInMinutes >= 5)
          telemetryFlush = true
        end

        if telemetryFlush
          ApplicationInsightsUtility.sendMetricTelemetry("PerfMetricCount", @@totalPerfCount, {"OS" => @@os_type})
          @cadvisorPerfTelemetryTicker = DateTime.now.to_time.to_i
          @@totalPerfCount = 0
        end


        #start GPU InsightsMetrics items
        begin
          if !@@isWindows.nil? && @@isWindows == false
            containerGPUusageInsightsMetricsDataItems = []
            containerGPUusageInsightsMetricsDataItems.concat(CAdvisorMetricsAPIClient.getInsightsMetrics(winNode: nil, namespaceFilteringMode: @namespaceFilteringMode, namespaces: @namespaces, metricTime: batchTime))

            containerGPUusageInsightsMetricsDataItems.each do |insightsMetricsRecord|
              insightsMetricsEventStream.add(time, insightsMetricsRecord) if insightsMetricsRecord
            end

            router.emit_stream(@insightsmetricstag, insightsMetricsEventStream) if !@insightsmetricstag.nil? && !@insightsmetricstag.empty? && insightsMetricsEventStream
            router.emit_stream(@mdmtag, insightsMetricsEventStream) if insightsMetricsEventStream

            if (!@@istestvar.nil? && !@@istestvar.empty? && @@istestvar.casecmp("true") == 0 && insightsMetricsEventStream.count > 0)
              $log.info("cAdvisorInsightsMetricsEmitStreamSuccess @ #{Time.now.utc.iso8601}")
            end
          end
        rescue => errorStr
          $log.warn "Failed when processing GPU Usage metrics in_cadvisor_perf : #{errorStr}"
          $log.debug_backtrace(errorStr.backtrace)
          ApplicationInsightsUtility.sendExceptionTelemetry(errorStr)
        end
        #end GPU InsightsMetrics items

      rescue => errorStr
        $log.warn "Failed to retrieve cadvisor metric data: #{errorStr}"
        $log.debug_backtrace(errorStr.backtrace)
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
            $log.info("in_cadvisor_perf::run_periodic.enumerate.start @ #{Time.now.utc.iso8601}")
            enumerate
            $log.info("in_cadvisor_perf::run_periodic.enumerate.end @ #{Time.now.utc.iso8601}")
          rescue => errorStr
            $log.warn "in_cadvisor_perf::run_periodic: enumerate Failed to retrieve cadvisor perf metrics: #{errorStr}"
          end
        end
        @mutex.lock
      end
      @mutex.unlock
    end
  end # CAdvisor_Perf_Input
end # module
