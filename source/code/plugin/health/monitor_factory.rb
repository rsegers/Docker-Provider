module HealthModel
    class MonitorFactory

        def initialize

        end

        def create_unit_monitor(monitor_record)
            return UnitMonitor.new(monitor_record.monitor_id,
                monitor_record.monitor_instance_id,
                monitor_record.state,
                monitor_record.transition_date_time,
                monitor_record.labels,
                monitor_record.config,
                monitor_record.details)
        end

        def create_aggregate_monitor(monitor_id, monitor_instance_id, labels, aggregation_algorithm, aggregation_algorithm_params, child_monitor)
            return AggregateMonitor.new(monitor_id,
                monitor_instance_id,
                child_monitor.state,
                child_monitor.transition_date_time,
                aggregation_algorithm,
                aggregation_algorithm_params,
                labels)
        end
    end
end