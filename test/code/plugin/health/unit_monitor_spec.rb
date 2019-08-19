require_relative '../../../../source/code/plugin/health/unit_monitor'
require_relative '../test_helpers'

include HealthModel

describe "UnitMonitor Spec" do
    it "is_aggregate_monitor is false for UnitMonitor" do
        # Arrange/Act
        monitor = UnitMonitor.new(:monitor_id, :monitor_instance_id, :pass, :time, {}, {}, {})
        # Assert
        assert_equal monitor.is_aggregate_monitor, false
    end

    it "get_member_monitors is nil for UnitMonitor" do
        # Arrange/Act
        monitor = UnitMonitor.new(:monitor_id, :monitor_instance_id, :pass, :time, {}, {}, {})
        #Assert
        assert_nil monitor.get_member_monitors
    end
end