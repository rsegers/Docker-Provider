require_relative 'health_model_constants'
require 'time'

module HealthModel
    class HealthModelBuilder
        attr_accessor :hierarchy_builder, :state_finalizers, :monitor_set

        def initialize(hierarchy_builder, state_finalizers, monitor_set)
            @hierarchy_builder = hierarchy_builder
            @state_finalizers = state_finalizers
            @monitor_set = monitor_set
        end

        def process_records(health_records)
            health_records.each{|health_record|
                @hierarchy_builder.process_record(health_record, @monitor_set)
            }
        end

        def finalize_model
            if !@state_finalizers.is_a?(Array)
                raise 'state finalizers should be an array'
            end

            if @state_finalizers.length == 0
                raise '@state_finalizers length should not be zero or empty'
            end

            @state_finalizers.each{|finalizer|
                finalizer.finalize(@monitor_set)
            }

            return @monitor_set.get_map
        end

    end
end