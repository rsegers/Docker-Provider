# Copyright (c) Microsoft Corporation.  All rights reserved.
#!/usr/local/bin/ruby
# frozen_string_literal: true

class ProxyUtils
    class << self
        def getProxyConfiguration()   
            omsproxy_secret_path = "/etc/omsagent-secret/PROXY"
            if !File.exist?(omsproxy_secret_path) 
              return {}
            end
      
            begin      
              proxy_config = parseProxyConfiguration(File.read(omsproxy_secret_path))
            rescue SystemCallError # Error::ENOENT
              return {}
            end
      
            if proxy_config.nil?
              $log.warn("Failed to parse the proxy configuration in '#{omsproxy_secret_path}'")
              return {}
            end
      
            return proxy_config
        end
        
        def parseProxyConfiguration(proxy_conf_str)
            # Remove the http(s) protocol
            proxy_conf_str = proxy_conf_str.gsub(/^(https?:\/\/)?/, "")
    
            # Check for unsupported protocol
            if proxy_conf_str[/^[a-z]+:\/\//]
              return nil
            end
    
            re = /^(?:(?<user>[^:]+):(?<pass>[^@]+)@)?(?<addr>[^:@]+)(?::(?<port>\d+))?$/ 
            matches = re.match(proxy_conf_str)
            if matches.nil? or matches[:addr].nil? 
              return nil
            end
            # Convert nammed matches to a hash
            Hash[ matches.names.map{ |name| name.to_sym}.zip( matches.captures ) ]
        end
    end
end