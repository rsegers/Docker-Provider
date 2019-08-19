require_relative '../../../../source/code/plugin/health/unit_monitor'
require_relative '../test_helpers'

class UnitMonitorTest < Minitest::Test
    include HealthModel

    def test_is_aggregate_monitor_false
        monitor = UnitMonitor.new(:monitor_id, :monitor_instance_id, :pass, :time, {}, {}, {})
        assert_equal monitor.is_aggregate_monitor, false
    end

    def test_get_member_monitors_nil
        monitor = UnitMonitor.new(:monitor_id, :monitor_instance_id, :pass, :time, {}, {}, {})
        assert_nil monitor.get_member_monitors
    end
end
