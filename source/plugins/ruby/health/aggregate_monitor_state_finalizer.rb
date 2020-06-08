# frozen_string_literal: true

module HealthModel
    class AggregateMonitorStateFinalizer

        def finalize(monitor_set)
            top_level_monitor = monitor_set.get_monitor(MonitorId::CLUSTER)
            if !top_level_monitor.nil?
                calculate_subtree_state(top_level_monitor, monitor_set)
            end
            monitor_set.get_map.each{|k,v|
                if v.is_aggregate_monitor
                    v.calculate_details(monitor_set)
                end
            }
        end

        private
        def calculate_subtree_state(monitor, monitor_set)
            if monitor.nil? || !monitor.is_aggregate_monitor
                raise 'AggregateMonitorStateFinalizer:calculateSubtreeState Parameter monitor must be non-null AggregateMonitor'
            end

            member_monitor_instance_ids = monitor.get_member_monitors # monitor_instance_ids
            member_monitor_instance_ids.each{|member_monitor_instance_id|
                member_monitor = monitor_set.get_monitor(member_monitor_instance_id)

                if !member_monitor.nil? && member_monitor.is_aggregate_monitor
                    calculate_subtree_state(member_monitor, monitor_set)
                end
            }
            monitor.calculate_state(monitor_set)
        end
    end
end