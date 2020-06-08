# frozen_string_literal: true
require 'yajl/json_gem'
module HealthModel
    class HealthMonitorOptimizer
        #ctor
        def initialize
            @@health_signal_timeout = 240
            @@first_record_sent = {}
        end

        def should_send(monitor_instance_id, health_monitor_state, health_monitor_config)

            health_monitor_instance_state = health_monitor_state.get_state(monitor_instance_id)
            health_monitor_records = health_monitor_instance_state.prev_records
            health_monitor_config['ConsecutiveSamplesForStateTransition'].nil? ? samples_to_check = 1 : samples_to_check = health_monitor_config['ConsecutiveSamplesForStateTransition'].to_i

            latest_record = health_monitor_records[health_monitor_records.size-1] #since we push new records to the end, and remove oldest records from the beginning
            latest_record_state = latest_record["state"]
            latest_record_time = latest_record["timestamp"] #string representation of time

            new_state = health_monitor_instance_state.new_state
            prev_sent_time = health_monitor_instance_state.prev_sent_record_time
            time_first_observed = health_monitor_instance_state.state_change_time

            if latest_record_state.downcase == new_state.downcase
                time_elapsed = (Time.parse(latest_record_time) - Time.parse(prev_sent_time)) / 60
                if time_elapsed > @@health_signal_timeout # minutes
                    return true
                elsif !@@first_record_sent.key?(monitor_instance_id)
                    @@first_record_sent[monitor_instance_id] = true
                    return true
                else
                    return false
                end
            else
                if samples_to_check == 1
                    return true
                elsif health_monitor_instance_state.prev_records.size == 1 && samples_to_check > 1
                    return true
                elsif health_monitor_instance_state.prev_records.size < samples_to_check
                    return false
                else
                    # state change from previous sent state to latest record state
                    #check state of last n records to see if they are all in the same state
                    if (health_monitor_instance_state.is_state_change_consistent)
                        return true
                    else
                        return false
                    end
                end
            end
        end
    end
end