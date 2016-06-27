# FIXME: files named with hyphens will not be found by Chamber for now
require "chamber"

module Shared
  class ConfigMissingParameter    < StandardError; end
  class ConfigOtherError          < StandardError; end
  class ConfigParseError          < StandardError; end
  class ConfigMultipleGemspec     < StandardError; end
  class ConfigMissingGemspec      < StandardError; end

  class Conf
    extend Chamber

    class << self
      attr_accessor :app_env
      attr_reader   :app_root
      attr_reader   :app_libs
      attr_reader   :app_name
      attr_reader   :app_ver
      attr_reader   :app_started
      attr_reader   :app_spec
      attr_reader   :files
      attr_reader   :host

    end

    def self.init app_root
      # Permanent flags
      @initialized  = true
      @app_started  = Time.now

      # Default values
      @files        ||= []
      @app_name     ||= "app_name"
      @app_env      ||= "production"
      @host         ||= `hostname`.to_s.chomp.split(".").first

      # Store and clean app_root
      @app_root = File.expand_path(app_root)

      # Try to find any gemspec file
      matches   = Dir["#{@app_root}/*.gemspec"]
      fail ConfigMissingGemspec, "gemspec file not found: #{gemspec_path}" if matches.size < 1
      fail ConfigMultipleGemspec, "gemspec file not found: #{gemspec_path}" if matches.size > 1

      # Load Gemspec (just the only match)
      @spec     = Gem::Specification::load(matches.first)
      @app_name = @spec.name
      @app_ver  = @spec.version
      fail ConfigMissingParameter, "gemspec: missing name" unless @app_name
      fail ConfigMissingParameter, "gemspec: missing version" unless @app_ver

      # Now we know app_name, initalize app_libs
      @app_libs = File.expand_path( @app_root + "/lib/#{@app_name}/" )

      # Add other config files
      add_default_config
      add_etc_config

      # Return something
      return @app_name
    end

    def self.prepare args = {}
      ensure_init

      # Add extra config file
      add_extra_config args[:config]

      # Load configuration files
      load_files

      # Init New Relic
      prepare_newrelic self[:newrelic], self.at(:logs, :newrelic)

      # Try to access any key to force parsing of the files
      self[:dummy]

    rescue Psych::SyntaxError => e
      fail ConfigParseError, e.message
    rescue StandardError => e
      fail ConfigOtherError, "#{e.message} \n #{e.backtrace.to_yaml}"
    end

    # Reload files
    def self.reload!
      ensure_init
      load_files
    end

    def self.dump
      ensure_init
      to_hash.to_yaml(indent: 4, useheader: true, useversion: false )
    end

    # Direct access to any depth
    def self.at *path
      ensure_init
      path.reduce(Conf) { |m, key| m && m[key.to_s] }
    end

    def self.newrelic_enabled?
      ensure_init
      !!self[:newrelic]
    end

    # Defaults generators
    def self.gen_pidfile
      ensure_init
      "/tmp/#{@app_name}-#{@host}-#{Process.pid}.pid"
    end
    def self.gen_process_name
      ensure_init
      "#{@app_name}/#{@app_env}/#{Process.pid}"
    end
    def self.gen_config_etc
      ensure_init
      "/etc/#{@app_name}.yml"
    end
    def self.gen_config_sample
      ensure_init
      "#{@app_root}/#{@app_name}.sample.yml"
    end
    def self.gen_config_message
      config_etc = gen_config_etc
      config_sample = gen_config_sample
      return "
A default configuration is available here: #{config_sample}.
You should copy it to the default location: #{config_etc}.
sudo cp #{config_sample} #{config_etc}
"
    end

  protected

    def self.load_files
      load files: @files, namespaces: { environment: @app_env }
    end

    def self.add_default_config
      @files << "#{@app_root}/defaults.yml" if @app_root
    end

    def self.add_etc_config
      @files << File.expand_path("/etc/#{@app_name}.yml") if @app_name
    end

    def self.add_extra_config path
      @files << File.expand_path(path) if path
    end

    def self.prepare_newrelic section, logfile
      # Disable NewRelic if no config present
      unless section.is_a?(Hash) && section[:licence]
        ENV["NEWRELIC_AGENT_ENABLED"] = "false"
        return
      end

      # Enable GC profiler
      GC::Profiler.enable

      # Enable module
      ENV["NEWRELIC_AGENT_ENABLED"] = "true"
      ENV["NEW_RELIC_MONITOR_MODE"] = "true"

      # License
      ENV["NEW_RELIC_LICENSE_KEY"] = section[:licence].to_s

      # Appname
      platform = section[:platform] || self.host
      section[:app_name] ||= "#{@app_name}-#{platform}-#{@app_env}"
      ENV["NEW_RELIC_APP_NAME"] = section[:app_name].to_s

      # Logfile
      ENV["NEW_RELIC_LOG"] = logfile.to_s if logfile
    end

  private

    def self.ensure_init
      # Skip is already done
      return if @initialized

      # Go through init if not already done
      self.init
    end

  end
end
