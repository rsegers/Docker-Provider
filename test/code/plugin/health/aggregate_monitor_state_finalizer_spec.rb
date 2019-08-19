require_relative '../test_helpers'
Dir[File.join(File.expand_path(File.dirname(__FILE__)), "../../../../source/code/plugin/health/*.rb")].reject{|f| f.include?('health_monitor_utils')}.each { |file| require file }
include HealthModel
include Minitest

describe "AggregateMonitorStateFinalizer spec" do
    it 'computes the right state and details' do
        #arrange
        monitor_set = Mock.new

        #mock unit monitors
        child1 = Mock.new
        def child1.state; "pass"; end
        def child1.monitor_id; "child1";end
        def child1.monitor_instance_id; "child1"; end
        def child1.nil?; false; end
        def child1.is_aggregate_monitor; false; end

        child2 = Mock.new
        def child2.state; "fail"; end
        def child2.monitor_id; "child2";end
        def child2.monitor_instance_id; "child2"; end
        def child2.nil?; false; end
        def child2.is_aggregate_monitor; false; end

        parent_monitor = AggregateMonitor.new("parent_monitor", "parent_monitor", :none, :time, "worstOf", nil, {})
        parent_monitor.add_member_monitor("child1")
        parent_monitor.add_member_monitor("child2")

        top_level_monitor = AggregateMonitor.new("cluster", "cluster", :none, :time, "worstOf", nil, {})
        top_level_monitor.add_member_monitor("parent_monitor")

        monitor_set.expect(:get_map, {"cluster" => top_level_monitor, "parent_monitor" => parent_monitor, "child1" => child1, "child2" => child2})
        monitor_set.expect(:get_monitor, top_level_monitor, ["cluster"])
        monitor_set.expect(:get_monitor, parent_monitor, ["parent_monitor"])
        monitor_set.expect(:get_monitor, child1, ["child1"])
        monitor_set.expect(:get_monitor, child2, ["child2"])
        monitor_set.expect(:get_monitor, child1, ["child1"])
        monitor_set.expect(:get_monitor, child2, ["child2"])
        monitor_set.expect(:get_monitor, parent_monitor, ["parent_monitor"])


        monitor_set.expect(:get_monitor, parent_monitor, ["parent_monitor"])
        monitor_set.expect(:get_monitor, child1, ["child1"])
        monitor_set.expect(:get_monitor, child2, ["child2"])

        #act
        finalizer = AggregateMonitorStateFinalizer.new
        finalizer.finalize(monitor_set)
        #assert

        assert_equal parent_monitor.state, "fail"
        assert_equal parent_monitor.details, {"details"=>{"pass"=>["child1"], "fail"=>["child2"]}, "state"=>"fail", "timestamp"=>:time}

        assert_equal top_level_monitor.state, "fail"
        assert_equal top_level_monitor.details, {"details"=>{"fail"=>["parent_monitor"]}, "state"=>"fail", "timestamp"=>:time}

    end
end