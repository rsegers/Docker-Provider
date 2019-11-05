# frozen_string_literal: true
=begin
    Class to parse the health model definition. The definition expresses the relationship between monitors, how to roll up to an aggregate monitor,
    and what labels to "pass on" to the parent monitor
=end
require 'json'

module HealthModel
    class HealthModelDefinitionParser
        attr_accessor :health_model_definition_path, :health_model_definition

        # Constructor
        def initialize(path)
            @health_model_definition = {}
            @health_model_definition_path = path
        end

        # Parse the health model definition file and build the model roll-up hierarchy
        def parse_file
            if (!File.exist?(@health_model_definition_path))
                raise "File does not exist in the specified path"
            end

            file = File.read(@health_model_definition_path)
            temp_model = JSON.parse(file)
            temp_model.each { |entry|
                monitor_id = entry['monitor_id']
                parent_monitor_id = entry['parent_monitor_id']
                labels = entry['labels']  if entry['labels']
                aggregation_algorithm = entry['aggregation_algorithm'] if entry['aggregation_algorithm']
                aggregation_algorithm_params = entry['aggregation_algorithm_params'] if entry['aggregation_algorithm_params']
                if parent_monitor_id.is_a?(Array)
                    conditions = []
                    parent_monitor_id.each{|condition|
                        key = condition['label']
                        operator = condition['operator']
                        value = condition['value']
                        parent_id = condition['id']
                        conditions.push({"key" => key, "operator" => operator, "value" => value, "parent_id" => parent_id})
                    }
                    @health_model_definition[monitor_id] = {"conditions" => conditions, "labels" => labels, "aggregation_algorithm" => aggregation_algorithm, "aggregation_algorithm_params" =>aggregation_algorithm_params}
                elsif parent_monitor_id.is_a?(String)
                    @health_model_definition[monitor_id] = {"parent_monitor_id" => parent_monitor_id, "labels" => labels, "aggregation_algorithm" => aggregation_algorithm, "aggregation_algorithm_params" =>aggregation_algorithm_params}
                elsif parent_monitor_id.nil?
                    @health_model_definition[monitor_id] = {"parent_monitor_id" => nil, "labels" => labels, "aggregation_algorithm" => aggregation_algorithm, "aggregation_algorithm_params" =>aggregation_algorithm_params}
                end
            }
            @health_model_definition
        end
    end
end