require_relative '../test_helpers'

Dir[File.join(File.expand_path(File.dirname(__FILE__)), "../../../../source/code/plugin/health/*.rb")].reject{|f| f.include?('health_monitor_utils')}.each { |file| require file }
include HealthModel

describe "AggregateMonitor Spec" do
    it "is_aggregate_monitor is true for AggregateMonitor" do
        # Arrange/Act
        monitor = AggregateMonitor.new(:monitor_id, :monitor_instance_id, :pass, :time, "worstOf", [], {})
        # Assert
        assert_equal monitor.is_aggregate_monitor, true
    end

    it "add_member_monitor tests -- adds a member monitor as a child monitor" do
        # Arrange
        monitor = AggregateMonitor.new(:monitor_id, :monitor_instance_id, :pass, :time, "worstOf", [], {})
        #Act
        monitor.add_member_monitor("child_monitor_1")
        #Assert
        assert_equal monitor.get_member_monitors.include?("child_monitor_1"), true

        #Act
        monitor.add_member_monitor("child_monitor_1")
        #Assert
        assert_equal monitor.get_member_monitors.size, 1
    end

    it "remove_member_monitor tests -- removes a member monitor as a child monitor" do
        # Arrange
        monitor = AggregateMonitor.new(:monitor_id, :monitor_instance_id, :pass, :time, "worstOf", [], {})
        monitor.add_member_monitor("child_monitor_1")
        monitor.add_member_monitor("child_monitor_2")

        #Act
        monitor.remove_member_monitor("child_monitor_1")
        #Assert
        assert_equal monitor.get_member_monitors.size, 1

        #Act
        monitor.remove_member_monitor("unknown_child")
        #Assert
        assert_equal monitor.get_member_monitors.size, 1
    end

    it "calculate_details tests -- calculates rollup details based on member monitor states" do
        # Arrange
        monitor = AggregateMonitor.new(:monitor_id, :monitor_instance_id, :pass, :time, "worstOf", [], {})

        child_monitor_1 = UnitMonitor.new("monitor_1", "child_monitor_1", "pass", "time", {}, {}, {})
        child_monitor_2 = UnitMonitor.new("monitor_2", "child_monitor_2", "fail", "time", {}, {}, {})

        monitor_set = MonitorSet.new
        monitor_set.add_or_update(child_monitor_1)
        monitor_set.add_or_update(child_monitor_2)

        monitor.add_member_monitor("child_monitor_1")
        monitor.add_member_monitor("child_monitor_2")

        #Act
        monitor.calculate_details(monitor_set)
        #Assert
        assert_equal monitor.details["details"], {"pass"=>["child_monitor_1"], "fail"=>["child_monitor_2"]}

        #Arrange
        child_monitor_3 = UnitMonitor.new("monitor_3", "child_monitor_3", "pass", "time", {}, {}, {})
        monitor_set.add_or_update(child_monitor_3)
        monitor.add_member_monitor("child_monitor_3")

        #Act
        monitor.calculate_details(monitor_set)
        #Assert
        assert_equal monitor.details["details"], {"pass"=>["child_monitor_1", "child_monitor_3"], "fail"=>["child_monitor_2"]}
    end

    it "calculate_state tests -- raises when right aggregation_algorithm NOT specified" do
        # Arrange
        monitor = AggregateMonitor.new(:monitor_id, :monitor_instance_id, :pass, :time, "", [], {})
        #Assert
        assert_raises do
            monitor.calculate_state(monitor_set)
        end
    end

    it "calculate_state tests -- calculate_worst_of_state " do
        # Arrange -- pass, fail = fail
        monitor = AggregateMonitor.new(:monitor_id, :monitor_instance_id, :pass, :time, "worstOf", [], {})

        child_monitor_1 = UnitMonitor.new("monitor_1", "child_monitor_1", "pass", "time", {}, {}, {})
        child_monitor_2 = UnitMonitor.new("monitor_2", "child_monitor_2", "fail", "time", {}, {}, {})

        monitor_set = MonitorSet.new
        monitor_set.add_or_update(child_monitor_1)
        monitor_set.add_or_update(child_monitor_2)

        monitor.add_member_monitor("child_monitor_1")
        monitor.add_member_monitor("child_monitor_2")
        #Act
        monitor.calculate_state(monitor_set)
        #Assert
        assert_equal monitor.state, "fail"

        #Arrange -- pass, pass = pass
        child_monitor_2 = UnitMonitor.new("monitor_2", "child_monitor_2", "pass", "time", {}, {}, {})
        monitor_set.add_or_update(child_monitor_2)
        #Act
        monitor.calculate_state(monitor_set)
        #Assert
        assert_equal monitor.state, "pass"

        #Arrange -- pass, warn = warn
        child_monitor_2 = UnitMonitor.new("monitor_2", "child_monitor_2", "warn", "time", {}, {}, {})
        monitor_set.add_or_update(child_monitor_2)
        #Act
        monitor.calculate_state(monitor_set)
        #Assert
        assert_equal monitor.state, "warn"

        #Arrange -- warn, fail = fail
        child_monitor_1 = UnitMonitor.new("monitor_1", "child_monitor_1", "warn", "time", {}, {}, {})
        child_monitor_2 = UnitMonitor.new("monitor_2", "child_monitor_2", "fail", "time", {}, {}, {})
        monitor_set.add_or_update(child_monitor_1)
        monitor_set.add_or_update(child_monitor_2)

        #Act
        monitor.calculate_state(monitor_set)
        #Assert
        assert_equal monitor.state, "fail"

        #Arrange -- warn, unknown = unknown
        child_monitor_1 = UnitMonitor.new("monitor_1", "child_monitor_1", "warn", "time", {}, {}, {})
        child_monitor_2 = UnitMonitor.new("monitor_2", "child_monitor_2", "unknown", "time", {}, {}, {})
        monitor_set.add_or_update(child_monitor_1)
        monitor_set.add_or_update(child_monitor_2)

        #Act
        monitor.calculate_state(monitor_set)
        #Assert
        assert_equal monitor.state, "warn"

        #Arrange -- pass, unknown = unknown
        child_monitor_1 = UnitMonitor.new("monitor_1", "child_monitor_1", "pass", "time", {}, {}, {})
        child_monitor_2 = UnitMonitor.new("monitor_2", "child_monitor_2", "unknown", "time", {}, {}, {})
        monitor_set.add_or_update(child_monitor_1)
        monitor_set.add_or_update(child_monitor_2)

        #Act
        monitor.calculate_state(monitor_set)
        #Assert
        assert_equal monitor.state, "unknown"
    end

    it "calculate_state tests -- calculate_percentage_state " do
        # Arrange
        monitor = AggregateMonitor.new(:monitor_id, :monitor_instance_id, :pass, :time, "percentage", {"state_threshold" => 90.0}, {})

        child_monitor_1 = UnitMonitor.new("monitor_1", "child_monitor_1", "pass", "time", {}, {}, {})
        child_monitor_2 = UnitMonitor.new("monitor_2", "child_monitor_2", "fail", "time", {}, {}, {})

        monitor_set = MonitorSet.new
        monitor_set.add_or_update(child_monitor_1)
        monitor_set.add_or_update(child_monitor_2)

        monitor.add_member_monitor("child_monitor_1")
        monitor.add_member_monitor("child_monitor_2")
        #Act
        monitor.calculate_state(monitor_set)
        #Assert
        assert_equal monitor.state, "fail"

        #Arrange
        monitor = AggregateMonitor.new(:monitor_id, :monitor_instance_id, :pass, :time, "percentage", {"state_threshold" => 50.0}, {})
        child_monitor_1 = UnitMonitor.new("monitor_1", "child_monitor_1", "pass", "time", {}, {}, {})
        child_monitor_2 = UnitMonitor.new("monitor_2", "child_monitor_2", "fail", "time", {}, {}, {})

        monitor_set = MonitorSet.new
        monitor_set.add_or_update(child_monitor_1)
        monitor_set.add_or_update(child_monitor_2)

        monitor.add_member_monitor("child_monitor_1")
        monitor.add_member_monitor("child_monitor_2")
        #Act
        monitor.calculate_state(monitor_set)
        #Assert
        assert_equal monitor.state, "pass"

        #Arrange -- single child monitor
        monitor = AggregateMonitor.new(:monitor_id, :monitor_instance_id, :pass, :time, "percentage", {"state_threshold" => 33.3}, {})
        child_monitor_1 = UnitMonitor.new("monitor_1", "child_monitor_1", "pass", "time", {}, {}, {})
        monitor_set = MonitorSet.new
        monitor_set.add_or_update(child_monitor_1)
        monitor.add_member_monitor("child_monitor_1")
        #Act
        monitor.calculate_state(monitor_set)
        #Assert
        assert_equal monitor.state, "pass"


        #Arrange -- remove none state
        monitor = AggregateMonitor.new(:monitor_id, :monitor_instance_id, :none, :time, "percentage", {"state_threshold" => 100.0}, {})
        child_monitor_1 = UnitMonitor.new("monitor_1", "child_monitor_1", "pass", "time", {}, {}, {})
        child_monitor_2 = UnitMonitor.new("monitor_2", "child_monitor_2", "none", "time", {}, {}, {})

        monitor_set = MonitorSet.new
        monitor_set.add_or_update(child_monitor_1)
        monitor_set.add_or_update(child_monitor_2)

        monitor.add_member_monitor("child_monitor_1")
        monitor.add_member_monitor("child_monitor_2")
        #Act
        monitor.calculate_state(monitor_set)
        #Assert
        assert_equal monitor.state, "pass"


        # Arrange
        monitor = AggregateMonitor.new(:monitor_id, :monitor_instance_id, :pass, :time, "percentage", {"state_threshold" => 50.0}, {})

        child_monitor_1 = UnitMonitor.new("monitor_1", "child_monitor_1", "pass", "time", {}, {}, {})
        child_monitor_2 = UnitMonitor.new("monitor_2", "child_monitor_2", "fail", "time", {}, {}, {})
        child_monitor_3 = UnitMonitor.new("monitor_3", "child_monitor_3", "fail", "time", {}, {}, {})

        monitor_set = MonitorSet.new
        monitor_set.add_or_update(child_monitor_1)
        monitor_set.add_or_update(child_monitor_2)
        monitor_set.add_or_update(child_monitor_3)

        monitor.add_member_monitor("child_monitor_1")
        monitor.add_member_monitor("child_monitor_2")
        monitor.add_member_monitor("child_monitor_3")
        #Act
        monitor.calculate_state(monitor_set)
        #Assert
        assert_equal monitor.state, "fail"


        # Arrange
        monitor = AggregateMonitor.new(:monitor_id, :monitor_instance_id, :pass, :time, "percentage", {"state_threshold" => 90.0}, {})

        child_monitor_1 = UnitMonitor.new("monitor_1", "child_monitor_1", "pass", "time", {}, {}, {})
        child_monitor_2 = UnitMonitor.new("monitor_2", "child_monitor_2", "pass", "time", {}, {}, {})
        child_monitor_3 = UnitMonitor.new("monitor_3", "child_monitor_3", "pass", "time", {}, {}, {})

        monitor_set = MonitorSet.new
        monitor_set.add_or_update(child_monitor_1)
        monitor_set.add_or_update(child_monitor_2)
        monitor_set.add_or_update(child_monitor_3)

        monitor.add_member_monitor("child_monitor_1")
        monitor.add_member_monitor("child_monitor_2")
        monitor.add_member_monitor("child_monitor_3")
        #Act
        monitor.calculate_state(monitor_set)
        #Assert
        assert_equal monitor.state, "pass"
    end
end