# frozen_string_literal: true

module HealthModel
  class MonitorSet
    attr_accessor :monitors

    #constructor
    def initialize
      @monitors = {}
    end

    # checks if the monitor is present in the set
    def contains?(monitor_instance_id)
      @monitors.key?(monitor_instance_id)
    end

    # adds or updates the monitor
    def add_or_update(monitor)
        @monitors[monitor.monitor_instance_id] = monitor
    end

    # gets the monitor given the monitor instance id
    def get_monitor(monitor_instance_id)
      @monitors[monitor_instance_id] if @monitors.key?(monitor_instance_id)
    end

    # deletes a monitor from the set
    def delete(monitor_instance_id)
      if @monitors.key?(monitor_instance_id)
        @monitors.delete(monitor_instance_id)
      end
    end

    # gets the size of the monitor set
    def get_size
      @monitors.length
    end

    # gets the map of monitor instance id to monitors
    def get_map
        @monitors
    end
  end
end
