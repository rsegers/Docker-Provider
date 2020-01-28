# Copyright (c) Microsoft Corporation.  All rights reserved.

# frozen_string_literal: true

require 'logger'
require 'yajl/json_gem'
require_relative 'oms_common'
require_relative 'CustomMetricsUtils'


class Inventory2MdmConvertor

    @@node_count_metric_name = 'nodesCount'
    @@pod_count_metric_name = 'podCount'
    @@pod_inventory_tag = 'mdm.kubepodinventory'
    @@node_inventory_tag = 'mdm.kubenodeinventory'
    @@node_status_ready = 'Ready'
    @@node_status_not_ready = 'NotReady'

    @@node_inventory_custom_metrics_template = '
        {
            "time": "%{timestamp}",
            "data": {
                "baseData": {
                    "metric": "%{metricName}",
                    "namespace": "insights.container/nodes",
                    "dimNames": [
                    "status"
                    ],
                    "series": [
                    {
                        "dimValues": [
                        "%{statusValue}"
                        ],
                        "min": %{node_status_count},
                        "max": %{node_status_count},
                        "sum": %{node_status_count},
                        "count": 1
                    }
                    ]
                }
            }
        }'

    @@pod_inventory_custom_metrics_template = '
        {
            "time": "%{timestamp}",
            "data": {
                "baseData": {
                    "metric": "%{metricName}",
                    "namespace": "insights.container/pods",
                    "dimNames": [
                    "phase",
                    "Kubernetes namespace",
                    "node",
                    "controllerName"
                    ],
                    "series": [
                    {
                        "dimValues": [
                        "%{phaseDimValue}",
                        "%{namespaceDimValue}",
                        "%{nodeDimValue}",
                        "%{controllerNameDimValue}"
                        ],
                        "min": %{podCountMetricValue},
                        "max": %{podCountMetricValue},
                        "sum": %{podCountMetricValue},
                        "count": 1
                    }
                    ]
                }
            }
        }'

    @@pod_phase_values = ['Running', 'Pending', 'Succeeded', 'Failed', 'Unknown']
    @process_incoming_stream = false

    def initialize(custom_metrics_azure_regions)
        @log_path = '/var/opt/microsoft/docker-cimprov/log/filter_inventory2mdm.log'
        @log = Logger.new(@log_path, 1, 5000000)
        @pod_count_hash = {}
        @no_phase_dim_values_hash = {}
        @pod_count_by_phase = {}
        @pod_uids = {}
        @process_incoming_stream = CustomMetricsUtils.check_custom_metrics_availability(custom_metrics_azure_regions)
        @log.debug "After check_custom_metrics_availability process_incoming_stream #{@process_incoming_stream}"
        @log.debug {'Starting filter_inventory2mdm plugin'}
    end

    def get_pod_inventory_mdm_records(batch_time)
        begin
            # generate all possible values of non_phase_dim_values X pod Phases and zero-fill the ones that are not already present
            @no_phase_dim_values_hash.each {|key, value|
                @@pod_phase_values.each{|phase|
                    pod_key = [key, phase].join('~~')
                    if !@pod_count_hash.key?(pod_key)
                        @pod_count_hash[pod_key] = 0
                        #@log.info "Zero filled #{pod_key}"
                    else
                        next
                    end
                }
            }
            records = []
            @pod_count_hash.each {|key, value|
                key_elements = key.split('~~')
                if key_elements.length != 4
                    next
                end

                # get dimension values by key
                podNodeDimValue = key_elements[0]
                podNamespaceDimValue = key_elements[1]
                podControllerNameDimValue = key_elements[2]
                podPhaseDimValue = key_elements[3]

                record = @@pod_inventory_custom_metrics_template % {
                    timestamp: batch_time,
                    metricName: @@pod_count_metric_name,
                    phaseDimValue: podPhaseDimValue,
                    namespaceDimValue: podNamespaceDimValue,
                    nodeDimValue: podNodeDimValue,
                    controllerNameDimValue: podControllerNameDimValue,
                    podCountMetricValue: value
                }
                records.push(JSON.parse(record))
            }
        rescue Exception => e
            @log.info "Error processing pod inventory record Exception: #{e.class} Message: #{e.message}"
            ApplicationInsightsUtility.sendExceptionTelemetry(e.backtrace)
            return []
        end
        @log.info "Pod Count To Phase #{@pod_count_by_phase} "
        @log.info "resetting convertor state "
        @pod_count_hash = {}
        @no_phase_dim_values_hash = {}
        @pod_count_by_phase = {}
        @pod_uids = {}
        return records
    end

    def process_pod_inventory_record(record)
        if @process_incoming_stream
            begin
                records = []

                podUid = record['DataItems'][0]['PodUid']
                if @pod_uids.key?(podUid)
                    #@log.info "pod with #{podUid} already counted"
                    return
                end

                @pod_uids[podUid] = true
                podPhaseDimValue = record['DataItems'][0]['PodStatus']
                podNamespaceDimValue = record['DataItems'][0]['Namespace']
                podControllerNameDimValue = record['DataItems'][0]['ControllerName']
                podNodeDimValue = record['DataItems'][0]['Computer']

                if podControllerNameDimValue.nil? || podControllerNameDimValue.empty?
                    podControllerNameDimValue = 'No Controller'
                end

                if podNodeDimValue.empty? && podPhaseDimValue.downcase == 'pending'
                    podNodeDimValue = 'unscheduled'
                elsif podNodeDimValue.empty?
                    podNodeDimValue = 'unknown'
                end

                # group by distinct dimension values
                pod_key = [podNodeDimValue, podNamespaceDimValue, podControllerNameDimValue, podPhaseDimValue].join('~~')

                @pod_count_by_phase[podPhaseDimValue] = @pod_count_by_phase.key?(podPhaseDimValue) ? @pod_count_by_phase[podPhaseDimValue] + 1 : 1
                @pod_count_hash[pod_key] = @pod_count_hash.key?(pod_key) ? @pod_count_hash[pod_key] + 1 : 1

                # Collect all possible combinations of dimension values other than pod phase
                key_without_phase_dim_value = [podNodeDimValue, podNamespaceDimValue, podControllerNameDimValue].join('~~')
                if @no_phase_dim_values_hash.key?(key_without_phase_dim_value)
                    return
                else
                    @no_phase_dim_values_hash[key_without_phase_dim_value] = true
                end
            rescue Exception => e
                @log.info "Error processing pod inventory record Exception: #{e.class} Message: #{e.message}"
                ApplicationInsightsUtility.sendExceptionTelemetry(e.backtrace)
            end
        end
    end
end

