# Copyright (c) Microsoft Corporation.  All rights reserved.
#!/usr/local/bin/ruby
# frozen_string_literal: true

require_relative 'CAdvisorMetricsAPIClient'

class KubeletUtils
    class << self
        def get_node_capacity

            cpu_capacity = 1.0
            memory_capacity = 1.0

            response = CAdvisorMetricsAPIClient.getNodeCapacityFromCAdvisor(winNode: nil)
            if !response.nil? && !response.body.nil?
                cpu_capacity = JSON.parse(response.body)["num_cores"].nil? ? 1.0 : (JSON.parse(response.body)["num_cores"] * 1000.0)
                memory_capacity = JSON.parse(response.body)["memory_capacity"].nil? ? 1.0 : JSON.parse(response.body)["memory_capacity"].to_f
                $log.info "CPU = #{cpu_capacity}mc Memory = #{memory_capacity/1024/1024}MB"
                return [cpu_capacity, memory_capacity]
            end
        end
    end
end