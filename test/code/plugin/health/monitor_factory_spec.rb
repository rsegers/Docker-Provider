require_relative '../test_helpers'
# consider doing this in test_helpers.rb so that this code is common
Dir[File.join(File.expand_path(File.dirname(__FILE__)), "../../../../source/code/plugin/health/*.rb")].reject{|f| f.include?('health_monitor_utils')}.each { |file| require file }
include HealthModel

describe "MonitorFactory Spec" do
    it "returns UnitMonitor for create_unit_monitor" do
        #Arrange
        factory = MonitorFactory.new()
        monitor_record = HealthMonitorRecord.new(:monitor_id, :monitor_instance_id, :time, :pass, {}, {}, {})
        #act
        monitor = factory.create_unit_monitor(monitor_record)
        # assert
        monitor.must_be_kind_of(UnitMonitor)
    end

    it "returns AggregateMonitor for create_aggregate_monitor" do
        #arrange
        factory = MonitorFactory.new()
        mock = Minitest::Mock.new
        def mock.state; :pass; end
        def mock.transition_date_time; :time; end
        #act
        monitor = factory.create_aggregate_monitor(:monitor_id, :monitor_instance_id, :pass, {}, {}, mock)
        #assert
        monitor.must_be_kind_of(AggregateMonitor)
    end
end