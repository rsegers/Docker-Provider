# frozen_string_literal: true

require 'test/unit'
require 'json'
# require_relative '../../../source/plugins/ruby/health'

Dir[File.join(__dir__, '../../../source/plugins/ruby/health', '*.rb')].each { |file| require file }

class FilterHealthModelBuilderTest < Test::Unit::TestCase
  include HealthModel

  def test_event_stream
    health_definition_path = 'C:\AzureMonitor\ContainerInsights\Docker-Provider\installer\conf\health_model_definition.json'
    health_model_definition = ParentMonitorProvider.new(HealthModelDefinitionParser.new(health_definition_path).parse_file)
    monitor_factory = MonitorFactory.new
    hierarchy_builder = HealthHierarchyBuilder.new(health_model_definition, monitor_factory)
    # TODO: Figure out if we need to add NodeMonitorHierarchyReducer to the list of finalizers. For now, dont compress/optimize, since it becomes impossible to construct the model on the UX side
    state_finalizers = [AggregateMonitorStateFinalizer.new]
    monitor_set = MonitorSet.new
    model_builder = HealthModelBuilder.new(hierarchy_builder, state_finalizers, monitor_set)

    i = 1
    loop do
        mock_data_path = "C:/AzureMonitor/ContainerInsights/Docker-Provider/source/plugins/ruby/mock_data-#{i}.json"
        file = File.read(mock_data_path)
        data = JSON.parse(file)

        health_monitor_records = []
        data.each do |record|
        health_monitor_record = HealthMonitorRecord.new(
            record[HealthMonitorRecordFields::MONITOR_ID],
            record[HealthMonitorRecordFields::MONITOR_INSTANCE_ID],
            record[HealthMonitorRecordFields::TIME_FIRST_OBSERVED],
            record[HealthMonitorRecordFields::DETAILS]["state"],
            record[HealthMonitorRecordFields::MONITOR_LABELS],
            record[HealthMonitorRecordFields::MONITOR_CONFIG],
            record[HealthMonitorRecordFields::DETAILS]
        )
        state_transitions.push(state_transition)
        end

        model_builder.process_state_transitions(state_transitions)
        changed_monitors = model_builder.finalize_model
        changed_monitors.keys.each{|key|
            puts key
        }
        i = i + 1
        if i == 6
            break
        end
    end
    puts "Done"
  end
end
