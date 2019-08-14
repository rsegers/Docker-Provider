require 'json'
module HealthModel
    class HealthHierarchyBuilder

        attr_accessor :health_model_definition, :monitor_factory

        def initialize(health_model_definition, monitor_factory)

            if !health_model_definition.is_a?(ParentMonitorProvider)
                raise "Invalid Type Expected: ParentMonitorProvider Actual: #{@health_model_definition.class.name}"
            end
            @health_model_definition = health_model_definition

            if !monitor_factory.is_a?(MonitorFactory)
                raise "Invalid Type Expected: MonitorFactory Actual: #{@monitor_factory.class.name}"
            end
            @monitor_factory = monitor_factory
        end

        def process_record(health_monitor_record, monitor_set)
            if !health_monitor_record.is_a?(HealthMonitorRecord)
                raise "Unexpected Type #{health_monitor_record.class}"
            end

            # monitor state transition will always be on a unit monitor
            child_monitor = @monitor_factory.create_unit_monitor(health_monitor_record)
            monitor_set.add_or_update(child_monitor)
            parent_monitor_id = @health_model_definition.get_parent_monitor_id(child_monitor)
            monitor_labels = child_monitor.labels
            monitor_id = child_monitor.monitor_id

            # to construct the parent monitor,
            # 1. Child's labels
            # 2. Parent monitor's config to determine what labels to copy
            # 3. Parent Monitor Id
            # 4. Monitor Id --> Labels to hash Mapping to generate the monitor instance id for aggregate monitors

            while !parent_monitor_id.nil?
                #puts "Parent Monitor Id #{parent_monitor_id}"
                # get the set of labels to copy to parent monitor
                parent_monitor_labels = @health_model_definition.get_parent_monitor_labels(monitor_id, monitor_labels, parent_monitor_id)
                # get the parent monitor configuration
                parent_monitor_configuration = @health_model_definition.get_parent_monitor_config(parent_monitor_id)
                #get monitor instance id for parent monitor. Does this belong in ParentMonitorProvider?
                parent_monitor_instance_id = @health_model_definition.get_parent_monitor_instance_id(child_monitor.monitor_instance_id, parent_monitor_id, parent_monitor_labels)
                # check if monitor set has the parent monitor id
                # if not present, add
                # if present, update the state based on the aggregation algorithm
                parent_monitor = nil
                if !monitor_set.contains?(parent_monitor_instance_id)
                    parent_monitor = @monitor_factory.create_aggregate_monitor(parent_monitor_id, parent_monitor_instance_id, parent_monitor_labels, parent_monitor_configuration['aggregation_algorithm'], parent_monitor_configuration['aggregation_algorithm_params'], child_monitor)
                    parent_monitor.add_member_monitor(child_monitor.monitor_instance_id)
                else
                    parent_monitor = monitor_set.get_monitor(parent_monitor_instance_id)
                    # required to calculate the rollup state
                    parent_monitor.add_member_monitor(child_monitor.monitor_instance_id)
                    # update to the earliest of the transition times of child monitors
                    if child_monitor.transition_date_time < parent_monitor.transition_date_time
                        parent_monitor.transition_date_time = child_monitor.transition_date_time
                    end
                end

                if parent_monitor.nil?
                    raise 'Parent_monitor should not be nil for #{monitor_id}'
                end

                monitor_set.add_or_update(parent_monitor)

                child_monitor = parent_monitor
                parent_monitor_id = @health_model_definition.get_parent_monitor_id(child_monitor)
                monitor_labels = child_monitor.labels
                monitor_id = child_monitor.monitor_id
            end
        end
    end
end