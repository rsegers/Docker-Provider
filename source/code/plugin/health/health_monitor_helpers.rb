require 'logger'
require 'digest'

module HealthModel
    # static class that provides a bunch of utility methods
    class HealthMonitorHelpers

        @log_path = "/var/opt/microsoft/docker-cimprov/log/health_monitors.log"

        if Gem.win_platform? #unit testing on windows dev machine
            @log_path = "C:\Temp\health_monitors.log"
        end

        @log = Logger.new(@log_path, 2, 10 * 1048576) #keep last 2 files, max log file size = 10M

        class << self
            def is_node_monitor(monitor_id)
                return (monitor_id == HealthMonitorConstants::NODE_CPU_MONITOR_ID || monitor_id == HealthMonitorConstants::NODE_MEMORY_MONITOR_ID || monitor_id == HealthMonitorConstants::NODE_CONDITION_MONITOR_ID)
            end

            def is_pods_ready_monitor(monitor_id)
                return (monitor_id == HealthMonitorConstants::USER_WORKLOAD_PODS_READY_MONITOR_ID || monitor_id == HealthMonitorConstants::SYSTEM_WORKLOAD_PODS_READY_MONITOR_ID)
            end

            def get_log_handle
                return @log
            end

            def get_monitor_instance_id(monitor_id, args = [])
                string_to_hash = args.join("/")
                return "#{monitor_id}-#{Digest::MD5.hexdigest(string_to_hash)}"
            end
        end

    end
end
