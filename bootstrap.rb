#!/usr/bin/env ruby
require 'erb'
require 'excon'

module Service
  class Base
    attr_reader :port

    def initialize(port)
      @port = port
    end

    def initialize(port)
      @port = port
    end

    def service_name
      self.class.name.downcase.split('::').last
    end

    def start
      ensure_directories
    end

    def ensure_directories
      %w{lib run log}.each do |dir|
        path = "/var/#{dir}/#{service_name}"
        Dir.mkdir(path) unless Dir.exists?(path)
      end
    end

    def data_directory
      "/var/lib/#{service_name}"
    end

    def pid_file
      "/var/run/#{service_name}/#{port}.pid"
    end


    def executable
      self.class.which(service_name)
    end

    def stop
      if File.exists?(pid_file)
        pid = File.read(pid_file).strip
        begin
          self.class.kill(pid.to_i)
        rescue => e
        end
      else
      end
    end

    def self.kill(pid, signal='SIGKILL')
      Process.kill(signal, pid)
    end

    def self.run_command(*args)
      pid = Process.fork
      if pid.nil? then
        exec args.join(" ")
      else
        Process.detach(pid)
      end
    end

    def self.which(executable)
      path = `which #{executable}`.strip
      if path == ""
        return nil
      else
        return path
      end
    end
  end


  class Tor < Base
    def data_directory
      "#{super}/#{port}"
    end

    def start
      super
      self.class.run_command(executable,
                             "--SocksPort #{port}",
                             "--NewCircuitPeriod 120",
                             "--DataDirectory #{data_directory}",
                             "--PidFile #{pid_file}",
                             '--RunAsDaemon 1')
    end
  end

  class Polipo < Base
    def initialize(port, tor:)
      super(port)
      @tor = tor
    end

    def start
      super
      self.class.run_command(executable,
                             "proxyPort=#{port}",
                             "socksParentProxy=127.0.0.1:#{tor_port}",
                             "socksProxyType=socks5",
                             "diskCacheRoot=''",
                             "disableLocalInterface=true",
                             "allowedClients=127.0.0.1",
                             "localDocumentRoot=''",
                             "disableConfiguration=true",
                             "dnsUseGethostbyname='yes'",
                             "logSyslog=true",
                             "logFile=/var/log/polipo.log",
                             "daemonise=true",
                             "pidFile=#{pid_file}",
                             "disableVia=true",
                             "allowedPorts='1-65535'",
                             "tunnelAllowedPorts='1-65535'")
    end

    def tor_port
      @tor.port
    end
  end

  class Proxy
    attr_reader :id
    attr_reader :tor, :polipo

    def initialize(id)
      @id = id
      @tor = Tor.new(tor_port)
      @polipo = Polipo.new(polipo_port, tor: tor)
    end

    def start
      @tor.start
      @polipo.start
    end

    def stop
      @tor.stop
      @polipo.stop
    end

    def restart
      stop
      sleep 2
      start
    end

    def tor_port
      10000 + id
    end


    def polipo_port
      tor_port + 10000
    end

    alias_method :port, :polipo_port

    def working?
      Excon.get('http://echoip.com', proxy: "http://127.0.0.1:#{port}").status == 200
    rescue
      false
    end
  end

  class Haproxy < Base
    attr_reader :tor_servers, :tor_exit_nodes

    def initialize(port = 3128)
      @config_ha = "/opt/haproxy.cfg"
      @config_tor = "/etc/tor/torrc"
      @tor_servers = []
      super(port)
    end

    def start
      super
      if ENV['geo']
        @tor_exit_nodes = ENV['geo'].split(',').map{|i| "{#{i}}"}.join(',')
      end

      File.write(@config_ha, ERB.new(File.new('/opt/haproxy.cfg.erb').read).result(binding))
      File.write(@config_tor, ERB.new(File.new('/opt/torrc.erb').read).result(binding))
      self.class.run_command(executable,
                             "-f #{@config_ha}")
    end

    def tor_proxy(proxy)
      @tor_servers << {:name => 'tor', :addr => '127.0.0.1', :port => proxy.port}
    end
  end
end


haproxy = Service::Haproxy.new
proxies = []

tor_instances = ENV['tors'] || 10

tor_instances.to_i.times.each do |id|
  proxy = Service::Proxy.new id
  haproxy.tor_proxy proxy
  proxy.start
  proxies << proxy
end

haproxy.start

sleep 10

loop do
  proxies.each do |proxy|
    proxy.restart unless proxy.working?
  end

  sleep 30
end
