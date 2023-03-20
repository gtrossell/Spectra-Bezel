#!/usr/bin/env ruby

require 'yaml'
require 'logger'

if $0 == __FILE__
  $LOAD_PATH.unshift(File.expand_path('../../', __FILE__))
end

# require 'spectra_support/cmd'

# require 'spectra_platform/bezel/fpframe'
require '.\\bezel\\fpframe'

# require 'spectra_platform/bezel/prom_cmd'
require '.\\bezel\\prom_cmd'

# require 'spectra_platform/bezel/time_cmd'
require '.\\bezel\\time_cmd'

# require 'spectra_platform/bezel/display_cmd'
require '.\\bezel\\display_cmd'

# require 'spectra_platform/bezel/jump_cmd'
require '.\\bezel\\jump_cmd'

module Spectra
  class Bezel

  FIRMWARE_VERSION = "0007"

    class << self
      attr_writer :logger
      def logger
        @logger ||= Logger.new(STDOUT)
      end
    end
  
    def logger
      self.class.logger
    end

    def self.find_device
      device = ""
      list = Cmd.run! "camcontrol devlist"
      list.out.each_line do |line|
        if line =~ /ATA Spectra.+(da\d+)\)/
          device =  $1
        end
      end
      device
    end

    def self.find_all_devices
      devices = []
      list = Cmd.run! "camcontrol devlist"
      list.out.each_line do |line|
        line.downcase!
        case line
        when /ata spectra.+(da\d+)/,
           ~ /ata strata.+(da\d+)/
          devices <<  "/dev/#{$1}"
        end
      end
      devices
    end

    def self.firmware_check(dev, version)
      if version != current_firmware_version
        Bezel.update_firmware(dev)
      else
        logger.debug "Firmware is up to date"
      end
    end

    def self.default_pattern_differs(dev)
      DisplayCmd.logger = logger
      differs = false
      y=YAML.load_file(File.dirname(__FILE__) + "/bezel/patterns/rainbow.yml")
      File.open(dev, "r+b") do |fh|
        y.each do |frame|
          read_cmd=DisplayCmd.new
          read_cmd.filehandle = fh
          read_cmd.command = DisplayCmd::READ_FRAME_COMMAND
          read_cmd.index = frame["number"]
          read_cmd.write_out
          read_cmd.read_from
          differs = true if read_cmd.next != frame["next_frame_number"]
          differs = true if read_cmd.duration != frame["duration"]
          for i in 0...32
            if read_cmd.leds[i].downcase != frame["led#{i}"].downcase
              differs = true 
            end
          end
          # We only need one difference in the whole pattern
          break if differs
        end
      end
      differs
    end

    def self.update_firmware(dev)
      PromCmd.logger = logger
      PromCmd.update_fw(File.dirname(__FILE__) + "/bezel/firmware/#{FIRMWARE_VERSION}.bin", dev)
    end

    def self.set_default_pattern(dev)
      DisplayCmd.logger = logger
      y=YAML.load_file(File.dirname(__FILE__) + "/bezel/patterns/rainbow.yml")
      DisplayCmd.default_from_yaml(y, dev)
    end

    def self.current_firmware_version
      FIRMWARE_VERSION
    end

    def self.sync_all_devices
      devices = find_all_devices
      for device in devices
        sync_time(device)
      end
      0
    end

    def self.display_ok(dev, color = "00FF00")
      DisplayCmd.logger = logger
      logger.debug "Bezel set to OK"
      y=YAML.load_file(File.dirname(__FILE__) + "/bezel/patterns/raindrop.yml")
      DisplayCmd.pattern_from_yaml(y, color, dev)
    end

    def self.display_warning(dev)
      DisplayCmd.logger = logger
      logger.debug "Bezel set to WARNING"
      y=YAML.load_file(File.dirname(__FILE__) + "/bezel/patterns/raindrop.yml")
      DisplayCmd.pattern_from_yaml(y, "ffff00", dev)
    end

    def self.display_tape_error(dev)
      DisplayCmd.logger = logger
      logger.debug "Bezel set to TAPE ERROR"
      y=YAML.load_file(File.dirname(__FILE__) + "/bezel/patterns/raindrop.yml")
      DisplayCmd.pattern_from_yaml(y, "ff4400", dev)
    end

    def self.display_error(dev)
      DisplayCmd.logger = logger
      logger.debug "Bezel set to ERROR"
      y=YAML.load_file(File.dirname(__FILE__) + "/bezel/patterns/raindrop.yml")
      DisplayCmd.pattern_from_yaml(y, "ff0000", dev)
    end
    
    def self.display_beacon(dev)
      DisplayCmd.logger = logger
      logger.debug "Bezel set to BEACON"
      y=YAML.load_file(File.dirname(__FILE__) + "/bezel/patterns/beacon.yml")
      DisplayCmd.display_from_yaml(y, dev)
    end

    def self.display_fw_update(dev)
      DisplayCmd.logger = logger
      logger.debug "Bezel set to FW_UPDATE"
      y=YAML.load_file(File.dirname(__FILE__) + "/bezel/patterns/firmware.yml")
      DisplayCmd.display_from_yaml(y, dev, DisplayCmd::FAILSAFE_LOCATION)
      frame_jump(DisplayCmd::FAILSAFE_LOCATION, dev, 0)
    end

    def self.display_default_set(dev)
      DisplayCmd.logger = logger
      logger.debug "Bezel set to DEFAULT_SET"
      y=YAML.load_file(File.dirname(__FILE__) + "/bezel/patterns/default_download.yml")
      DisplayCmd.display_from_yaml(y, dev, DisplayCmd::FAILSAFE_LOCATION)
      frame_jump(DisplayCmd::FAILSAFE_LOCATION, dev, 0)
    end

    def self.send_watchdog(dev)
      DisplayCmd.logger = logger
      logger.debug "Bezel set WATCHDOG"
      y=YAML.load_file(File.dirname(__FILE__) + "/bezel/patterns/watchdog.yml")
      DisplayCmd.display_from_yaml(y, dev, DisplayCmd::WATCHDOG_LOCATION)

      DisplayCmd.set_watchdog(dev)
    end

    def self.send_hotpair_watchdog(dev, color)
      # Since we have less bezel control in hotpair, set the watchdog to 
      # be the same as the OK pattern

      DisplayCmd.logger = logger
      logger.debug "Bezel set to WATCHDOG"
      y=YAML.load_file(File.dirname(__FILE__) + "/bezel/patterns/raindrop.yml")
      DisplayCmd.pattern_from_yaml(y, color, dev, DisplayCmd::WATCHDOG_LOCATION)

      DisplayCmd.set_watchdog(dev)
    end


    def self.frame_jump(frame, dev, time = nil)
      File.open(dev, "r+b") do |fh|
        f=JumpCmd.new
        f.filehandle = fh
        f.index = frame
        if time == 0
          #0 means jump immediately
          f.int_part = 0
        else
          t = TimeCmd.current_to_ntp(time)
          f.int_part = t[:int_part]
        end
        f.write_out
      end
    end

    def self.sync_time(dev)
      TimeCmd.logger = logger
      File.open(dev, "r+b") do |f|
        offset = TimeCmd.get_offset(f)
        logger.debug "Bezel cmd offset=#{offset}"
        skew = TimeCmd.calculate_skew(f, offset)
        logger.debug "#{dev} bezel set skew to #{skew}"
        TimeCmd.set_full_time(f, offset, skew)
      end
      0
    end

    def self.self_test 
      threads = []
      #bezels = [0,1,2,3,4,5,6,7]
      bezels = [0]
      bezels.each do |bezel|
        threads << Thread.new(bezel) {|t_bezel|
          #display_fw_update("/dev/da#{t_bezel}")
          #Maybe set the bezel status first
          #update_firmware("/dev/da#{t_bezel}")
          #set_default_pattern("/dev/da#{t_bezel}")
          #Spectra::Bezel.sync_time("/dev/da#{t_bezel}")
          #Spectra::Bezel.send_watchdog("/dev/da#{t_bezel}")
          #Spectra::Bezel.display_ok("/dev/da#{t_bezel}", "00ff00")
          y=YAML.load_file(File.dirname(__FILE__) + "/bezel/patterns/raindrop.yml")
          DisplayCmd.pattern_from_yaml(y, "00ff00", "/dev/da#{t_bezel}", 0)

          #frame_jump(1000, "/dev/da#{t_bezel}", 0)
        }
      end
      puts 'WAITNG'
      threads.each {|t| t.join}
      puts 'done'

      future_time = Time.now + 15
      bezels.each do |bezel|
        Spectra::Bezel.frame_jump(1000, "/dev/da#{bezel}", future_time)
      end

      0
    end

  end
end

exit(Spectra::Bezel.self_test) if $0 == __FILE__
