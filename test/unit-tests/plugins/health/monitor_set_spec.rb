require_relative '../test_helpers'
# consider doing this in test_helpers.rb so that this code is common
Dir[File.join(File.expand_path(File.dirname(__FILE__)), "../../../../source/plugins/ruby/health/*.rb")].reject{|f| f.include?('health_monitor_utils')}.each { |file| require file }
include HealthModel

describe "MonitorSet Spec" do
    it "add_or_update -- adds a monitor" do
        #arrange
        set = MonitorSet.new
        mock_monitor = MiniTest::Mock.new
        def mock_monitor.monitor_instance_id; "monitor_instance_id_1"; end
        def mock_monitor.state; :pass;end
        #act
        set.add_or_update(mock_monitor)
        #assert
        assert_equal set.get_map.size, 1
        assert_equal set.get_map.key?("monitor_instance_id_1"), true
    end

    it "add_or_update -- updates a monitor" do
        #arrange
        set = MonitorSet.new
        mock_monitor = MiniTest::Mock.new
        def mock_monitor.monitor_instance_id; "monitor_instance_id_1"; end
        def mock_monitor.state; :pass;end
        #act
        set.add_or_update(mock_monitor)
        #assert
        assert_equal set.get_map["monitor_instance_id_1"].state, :pass

        #act
        def mock_monitor.state; :fail;end
        set.add_or_update(mock_monitor)
        #assert
        assert_equal set.get_map["monitor_instance_id_1"].state, :fail
    end

    it "delete -- delete a monitor" do
        #arrange
        set = MonitorSet.new
        mock_monitor = MiniTest::Mock.new
        def mock_monitor.monitor_instance_id; "monitor_instance_id_1"; end
        def mock_monitor.state; :pass;end
        set.add_or_update(mock_monitor)

        #act
        set.delete("monitor_instance_id_1")
        #assert
        assert_equal set.get_map.size, 0
    end

    it "get_map -- returns a hash" do
        #arrange
        set = MonitorSet.new
        #act and assert
        set.get_map.must_be_kind_of(Hash)
    end
end
