#!/usr/local/bin/ruby
#
# Bezel Test program for old and new bezels.  It allows you to sync up multiple
# bezels by sending the same display commands.
#
# Author: Keith Oliver
#
# 1.0 - Initial creation
# 1.1 - Added FlashingBlue to Serial Bezel, cleaned up menu choices.

require 'os'
require 'optparse'

# require 'spectra_platform/serial_bezel'  # For New Bezel
require '.\\serial_bezel.rb'  # For New Bezel

# require 'spectra_platform/bezel'  # For Old Bezel


class SerialBezelTest
  attr_reader :old_bezel_devs
  attr_reader :new_bezel_devs

  attr_reader :old_bezels
  attr_reader :new_bezels
  
  attr_reader :bezel_mutex

  VERSION = 1.1

  def initialize(options = {})
    @bezel_mutex = Mutex.new
    @old_bezels = []
    @new_bezels = []

    @old_bezel_devs = options[:old_bezel_devs].nil? ? [] : options[:old_bezel_devs]
    @new_bezel_devs = options[:new_bezel_devs].nil? ? [] : options[:new_bezel_devs]
    validate(options)

    @old_bezels = @old_bezel_devs

    # Convert the new bezel devs to SerialBezel Objects
    @new_bezel_devs.each do |dev|
      b =  Spectra::SerialBezel.new(dev)
#      b.logger.level = Logger::DEBUG
      b.logger.level = Logger::ERROR
      @new_bezels << b
    end
  end

  def validate(options)
    if @old_bezel_devs.empty? && @new_bezel_devs.empty?
      raise "No Bezels Entered"
    end
  end

  # Helper Input Methods
  def get_integer(msg)
    puts "\n#{msg}"
    begin
      Integer($stdin.gets.chomp)
    rescue
      0
    end
  end

  # Returns true if yes false if no
  def get_yes_no(msg)
    puts "\n#{msg}"
    ans = $stdin.gets.chomp
    return false if ans.nil? || ans.empty?
    return true if ans.upcase.start_with?("Y")
    return false
  end

  # Gets user input.
  def get_string(msg)
    puts "\n#{msg}"
    $stdin.gets.chomp
  end

  # Returns the pattern and non zero for start at beginning.
  def get_pattern_at_inputs()
    b = get_yes_no("Do you want the pattern to start at the beginning (Y/N)?")
    beginning = b ? 1 : 0
    seconds = get_integer("To make things easier just enter the number of seconds from now you want the bezel to start the pattern.\nEnter number of seconds (positive or negative): ")
    time = Time.now + seconds

    return time, beginning
  end
  
  def get_identity()
    identity = {}
    @new_bezels.each do |nb|
      api_version, product = nb.get_identity()
      puts "Bezel: #{nb.dev}"
      puts "  API Version: #{api_version}"
      puts "  Product: #{product}"
      identity[nb.dev] = {:api_version => api_version,
                          :product     => product}
    end
    identity
  end
  
  def get_version_info()
    version_info = {}
    @new_bezels.each do |nb|
      serial_number, firmware, reserved, hardware, boot_loader = nb.get_version_info()
      puts "Bezel: #{nb.dev}"
      puts "  Serial Number: #{serial_number}"
      puts "  Firmware:      #{firmware}"
      puts "  Reserved:      #{reserved}"
      puts "  Hardware:      #{hardware}"
      puts "  Boot Loader:   #{boot_loader}"
      version_info[nb.dev] = {:serial_number => serial_number,
                              :firmware      => firmware,
                              :reserved      => reserved,
                              :hardware      => hardware,
                              :boot_loader   => boot_loader}
    end
    version_info
  end
  
  # Sets time of the bezel if nil current time is used.
  def set_time(time = nil)
    @new_bezels.each do |nb|
      nb.set_time(time)
    end
  end
  
  def get_time(display = true)
    times = {}
    threads = []
    @old_bezels.each do |ob|
      threads << Thread.new{File.open(ob, "r+b") do |f|
        t = Spectra::Bezel::TimeCmd.get_full_time(f, 0)
        if display
          puts "Bezel: #{ob}"
          puts "  #{Time.at(t)}  #{t} ms"
        end
        times[ob] = {:time => t}
      end
      }  # Thread Block 
    end
    threads.each {|t| t.join}
  
    @new_bezels.each do |nb|
      threads << Thread.new{t = nb.get_time()
      if display
        puts "Bezel: #{nb.dev}"
        puts "  #{Time.at(t.to_f / 1000.0)}   #{t} ms"
      end
      times[nb.dev] = {:time => t}
      } # Thread Block
    end

    threads.each {|t| t.join}
    times
  end
  
  def read_manufacturing_info()
    manufacturing_info = {}
    @new_bezels.each do |nb|
      fru_sn, ec_number = nb.read_manufacturing_info()
      puts "Bezel: #{nb.dev}"
      puts "  Fru Serial Number is: #{fru_sn}"
      puts "  EC Number is:         #{ec_number}"
      manufacturing_info[nb.dev] = {:fru_sn => fru_sn,
                                    :ec_number => ec_number}
    end
    return manufacturing_info
  end

  def get_time_difference
    times = {}
    @new_bezels.each do |nb|
      w_offset, r_offset, offset = nb.get_offset()
      sys_time = Time.now
      bezel_time = nb.get_time()
      puts "Bezel Time:  #{bezel_time - offset} System Time #{(sys_time.to_f * 1000).to_i}"
      times[nb.dev] = {:bezel_time => bezel_time + offset, :system_time => (sys_time.to_f * 1000).to_i}
    end
    times
  end

  def call_check_time_drift
    puts "Not Implemented Yet!!"
  end
 
  def get_offset
    offsets = {}
    threads = []
    @old_bezels.each do |ob|
      threads << Thread.new{File.open(ob, "r+b") do |f|
        offset = Spectra::Bezel::TimeCmd.get_offset(f)
        puts "Bezel: #{ob}"
        puts "  Offset: #{offset}"
        offsets[ob] = {:offset => offset}
      end
      }  # Thread Block 
    end
    threads.each {|t| t.join}
  
    @new_bezels.each do |nb|
      threads << Thread.new{w_offset, r_offset, offset = nb.get_offset()
      puts "Bezel: #{nb.dev}"
      puts "  Write Offset: #{w_offset} Read Offset: #{r_offset} Offset: #{offset}"
      offsets[nb.dev] = {:w_offset => w_offset, :r_offset => r_offset, :offset => offset}
      } # Thread Block
    end

    threads.each {|t| t.join}
    offsets 
  end

  def sync_time  # Old Bezel Only
    puts "Old Bezels only!!"
    threads = []
    @old_bezels.each do |ob|
      threads << Thread.new{Spectra::Bezel.sync_time(ob)}
    end
    threads.each {|t| t.join}
  rescue StandardError => e
    puts "Bezel Sync Time Error: #{e.message}"
  end

  def display_purple_scroll_with_delay(delay)
    # Overlay pattern on Old Bezel b/c New Bezel only starts at Current Frame when using delay so frame_jump is useless
    @old_bezels.each do |ob|
      Spectra::Bezel::display_ok(ob, "bb00ff")
    end
    threads = []
    @new_bezels.each do |nb|
      threads << Thread.new{nb.display_purple_scroll_with_delay(delay)}
    end
    threads.each {|t| t.join}
  end
  
  def display_yellow_scroll_with_delay(delay)
    # Overlay pattern on Old Bezel b/c New Bezel only starts at Current Frame when using delay so frame_jump is useless
    @old_bezels.each do |ob|
      Spectra::Bezel::display_warning(ob)
    end
    threads = []
    @new_bezels.each do |nb|
      threads << Thread.new{nb.display_yellow_scroll_with_delay(delay)}
    end
    threads.each {|t| t.join}
  end
  
  def display_red_scroll_with_delay(delay)
    # Overlay pattern on Old Bezel b/c New Bezel only starts at Current Frame when using delay so frame_jump is useless
    @old_bezels.each do |ob|
      Spectra::Bezel::display_error(ob)
    end
    threads = []
    @new_bezels.each do |nb|
      threads << Thread.new{nb.display_red_scroll_with_delay(delay)}
    end
    threads.each {|t| t.join}
  end
  
  def display_orange_scroll_with_delay(delay)
    # Overlay pattern on Old Bezel b/c New Bezel only starts at Current Frame when using delay so frame_jump is useless
    @old_bezels.each do |ob|
      Spectra::Bezel::display_tape_error(ob)
    end
    threads = []
    @new_bezels.each do |nb|
      threads << Thread.new{nb.display_orange_scroll_with_delay(delay)}
    end
    threads.each {|t| t.join}
  end

  def display_flashing_blue_with_delay(delay)
    @old_bezels.each do |ob|
      Spectra::Bezel.display_beacon(ob)
    end
    threads = []
    @new_bezels.each do |nb|
      threads << Thread.new{nb.display_flashing_blue_with_delay(delay)}
    end
    threads.each {|t| t.join}
  end
  
  def display_rainbow_scroll_with_delay(delay)
    threads = []
    time = 0
    # Create a time for the old Bezel if zero it it immediate.
    if delay != 0
      time = Time.now.to_f + delay
    end
    @old_bezels.each do |ob|
      threads << Thread.new{Spectra::Bezel.frame_jump(0, ob, time)}
    end
    @new_bezels.each do |nb|
      threads << Thread.new{nb.display_rainbow_scroll_with_delay(delay)}
    end
    threads.each {|t| t.join}
  end
  
  
  def display_pulsing_red_with_delay(delay)
    threads = []
    time = 0
    # Create a time for the old Bezel if zero it it immediate.
    if delay != 0
      time = Time.now.to_f + delay
    end
    @old_bezels.each do |ob|
      threads << Thread.new{Spectra::Bezel.frame_jump(Spectra::Bezel::DisplayCmd::WATCHDOG_LOCATION, ob, time)}
    end
    @new_bezels.each do |nb|
      threads << Thread.new{nb.display_pulsing_red_with_delay(delay)}
    end
    threads.each {|t| t.join}
  end
  
  def display_rgb_cycle_with_delay(delay)
    threads = []
    time = 0
    # Create a time for the old Bezel if zero it it immediate.
    if delay != 0
      time = Time.now.to_f + delay
    end
    @old_bezels.each do |ob|
      # Not sure how to to do this yet
    end
    @new_bezels.each do |nb|
      threads << Thread.new{nb.display_rgb_cycle_with_delay(delay)}
    end
    threads.each {|t| t.join}
  end
 
  def display_purple_scroll_at(time, beginning = 1)
    # First load the new pattern on the old bezes outside the thread
    @old_bezels.each do |ob|
      Spectra::Bezel::display_ok(ob, "bb00ff")
    end

    threads = []
    if beginning > 0
      @old_bezels.each do |ob|
        threads << Thread.new{Spectra::Bezel.frame_jump(Spectra::Bezel::DisplayCmd::MAIN_PATTERN_START, ob, time.to_f)}
      end
    end

    # Old bezel drops the ms from time so round down.
    ms = (time.to_i * 1000).to_i
    @new_bezels.each do |nb|
      threads << Thread.new{nb.display_purple_scroll_at(ms, beginning)}
    end
    threads.each {|t| t.join}
  end
  
 
  def display_yellow_scroll_at(time, beginning = 1)
    # First load the new pattern on the old bezes outside the thread
    @old_bezels.each do |ob|
      Spectra::Bezel::display_warning(ob)
    end

    threads = []
    if beginning > 0
      @old_bezels.each do |ob|
        threads << Thread.new{Spectra::Bezel.frame_jump(Spectra::Bezel::DisplayCmd::MAIN_PATTERN_START, ob, time.to_f)}
      end
    end
    # Old bezel drops the ms from time so round down.
    ms = (time.to_i * 1000).to_i
    @new_bezels.each do |nb|
      threads << Thread.new{nb.display_yellow_scroll_at(ms, beginning)}
    end
    threads.each {|t| t.join}
  end

  def display_red_scroll_at(time, beginning = 1)
    # First load the new pattern on the old bezes outside the thread
    @old_bezels.each do |ob|
      Spectra::Bezel::display_error(ob)
    end
    threads = []
    if beginning > 0
      @old_bezels.each do |ob|
        threads << Thread.new{Spectra::Bezel.frame_jump(Spectra::Bezel::DisplayCmd::MAIN_PATTERN_START, ob, time.to_f)}
      end
    end
    # Old bezel drops the ms from time so round down.
    ms = (time.to_i * 1000).to_i
    @new_bezels.each do |nb|
      threads << Thread.new{nb.display_red_scroll_at(ms, beginning)}
    end
    threads.each {|t| t.join}
  end

  def display_orange_scroll_at(time, beginning = 1)
    # First load the new pattern on the old bezes outside the thread
    @old_bezels.each do |ob|
      Spectra::Bezel::display_tape_error(ob)
    end
    threads = []
    if beginning > 0
      @old_bezels.each do |ob|
        threads << Thread.new{Spectra::Bezel.frame_jump(Spectra::Bezel::DisplayCmd::MAIN_PATTERN_START, ob, time.to_f)}
      end
    end
    # Old bezel drops the ms from time so round down.
    ms = (time.to_i * 1000).to_i
    @new_bezels.each do |nb|
      threads << Thread.new{nb.display_orange_scroll_at(ms, beginning)}
    end
    threads.each {|t| t.join}
  end

  def display_flashing_blue_at(time, beginning = 1)
    threads = []
    @old_bezels.each do |ob|
      Spectra::Bezel.display_beacon(ob)
    end

    threads = []
    if beginning > 0
      @old_bezels.each do |ob|
        threads << Thread.new{Spectra::Bezel.frame_jump(Spectra::Bezel::DisplayCmd::MAIN_PATTERN_START, ob, time.to_f)}
      end
    end
    # Old bezel drops the ms from time so round down.
    ms = (time.to_i * 1000).to_i
    @new_bezels.each do |nb|
      threads << Thread.new{nb.display_flashing_blue_at(ms, beginning)}
    end
    threads.each {|t| t.join}
  end

  def display_rainbow_scroll_at(time, beginning = 1)
    threads = []
    @old_bezels.each do |ob|
      threads << Thread.new{Spectra::Bezel.frame_jump(0, ob, time.to_f)}
    end
    # Old bezel drops the ms from time so round down.
    ms = (time.to_i * 1000).to_i
    @new_bezels.each do |nb|
      threads << Thread.new{nb.display_rainbow_scroll_at(ms, beginning)}
    end
    threads.each {|t| t.join}
  end

  def display_pulsing_red_at(time, beginning = 1)
    threads = []
    @old_bezels.each do |ob|
      threads << Thread.new{Spectra::Bezel.frame_jump(Spectra::Bezel::DisplayCmd::WATCHDOG_LOCATION, ob, time.to_f)}
    end
    # Old bezel drops the ms from time so round down.
    ms = (time.to_i * 1000).to_i
    @new_bezels.each do |nb|
      threads << Thread.new{nb.display_pulsing_red_at(ms, beginning)}
    end
    threads.each {|t| t.join}
  end

  def display_rgb_cycle_at(time, beginning = 1)
    threads = []
    @old_bezels.each do |ob|
      # Not sure how to to do this yet
    end
    # Old bezel drops the ms from time so round down.
    ms = (time.to_i * 1000).to_i
    @new_bezels.each do |nb|
      threads << Thread.new{nb.display_rgb_cycle_at(ms, beginning)}
    end
    threads.each {|t| t.join}
  end

  def get_current_pattern()
    patterns = {}
    @new_bezels.each do |nb|
      pattern = nb.get_current_pattern()
      puts "Bezel: #{nb.dev}"
      puts "  Pattern #{nb.map_pattern(pattern)}  #{pattern}"
      patterns[nb.dev] = {:pattern => pattern}
    end
    patterns
  end

  # Updates the FW on all bezels with the full path of the new FW file, if nil
  # or empty, the Gem will install the version contained in the GEM.
  def update_firmware(fw_file = nil)
    @new_bezels.each do |nb|
      serial_number, firmware, reserved, hardware, boot_loader = nb.get_version_info()
      nb.update_firmware(serial_number, fw_file)
    end
  end
  
  def enter_dfu_boot_loader()
    puts "To get Serial Number"
    puts "  dfu-util --list"
    puts "To load a new dfu file"
    puts "  dfu-util -a 0 -S \"<serial number>\" -D <filename>"
    puts "To exit dfu mode"
    puts "  dfu-util -a 0 -s 0x08000000 -S \"<serial number>\" -L   # Note: this will not exit with 0"
    @new_bezels.each do |nb|
      nb.send(:enter_dfu_boot_loader)
    end
  end

  # Leaves DFU mode
  # Input an array of bezel serial numbers.
  def leave_dfu_boot_loader(serial_numbers)
    serial_numbers.each do |sn|
      system("dfu-util -a 0 -s 0x08000000 -S \"#{sn}\" -L")
    end
  end

  def stop_zfs_worker
    system("monit stop zfs_worker")
  end

  def start_zfs_worker
    system("monit start zfs_worker")
  end

  def stop_all_services
    system("monit stop all")
  end

  def start_all_services
    system("monit start all")
  end



  # Method to send a command to the bezels every few seconds
  def keep_talking()
    Thread.new {
     loop do
       @bezel_mutex.synchronize do
         set_time()
       end
        sleep 60
      end
    } # Thread Block
  end

  # Sync all bezels once an hour (i.e start at beginning with purple)
  def keep_in_sync()
    Thread.new {
      loop do
        sec = (Time.now.to_i + 3).to_i
        @bezel_mutex.synchronize do
          display_purple_scroll_at(sec, 1)
        end
        sleep 3600  # 
      end
    } # Thread Block
  end

  def menu()
    system('clear')
    loop do
  
      puts "\n\n"
      puts "BEZEL MENU."
      puts
      puts "1  - Query for Identity String                 (New Bezel Only)"
      puts "2  - Query for Version Info                    (New Bezel Only)"
      puts "3  - Set Time to Current Time.                 (New Bezel Only)"
      puts "4  - Get Time from all bezels."
      puts "5  - Read Manufacturing Info                   (New Bezel Only)" 
      puts "6  - Get Time Difference                       (New Bezel Only)"
#KO      puts "7  - Sync Time Can take over a minute          (Old Bezel Only)"
#KO      puts "     ZfsWorker must be stopped"
#KO      puts ""
#KO      puts "DELAYS ONLY WORK ON NEW BEZEL B/C OLD BEZEL YOU OVERLAY A NEW PATTERN OR FRAME JUMP TO BEGINNING"
#KO      puts "SO DELAY IS NOT REALLY AN OPTION.  IF YOU WANT A DELAY YOU MUST USE COMMANDS 20 AND GREATER AND"
#KO      puts "SUPPLY A DELAY THERE"
#KO      puts "10 - Purple Scroll With Delay    (0x0001)"
#KO      puts "11 - Yellow Scroll With Delay    (0x0002)"
#KO      puts "12 - Red Scroll With Delay       (0x0003)"
#KO      puts "13 - Orange Scroll With Delay    (0x0004)"
#KO      puts "14 - Rainbow Scroll With Delay   (0x0005)"
#KO      puts "15 - Flashing Blue With Delay    (0x0006)"
#KO      puts "16 - Pulsing Red With Delay      (0x0007)"
#KO      puts "17 - RGB Cycle With Delay        (0x0100)      (New Bezel Only)"
      puts ""
      puts "20 - Purple Scroll At Time       (0x0001)"
      puts "21 - Yellow Scroll At Time       (0x0002)"
      puts "22 - Red Scroll At Time          (0x0003)"
      puts "23 - Orange Scroll At Time       (0x0004)"
      puts "24 - Rainbow Scroll At Time      (0x0005)"
      puts "25 - Flashing Blue At Time       (0x0006)"
      puts "26 - Pulsing Red At Time         (0x0007)"
      puts "27 - RGB Cycle At Time           (0x0100)      (New Bezel Only)"
      puts ""
      puts "30 - Get Current Pattern"
      puts ""
#KO      puts "40 - Update Firmware.                          (New Bezel Only)"
#KO      puts "41 - Enter Dfu Mode (0x0020)                   (New Bezel Only)"
#KO      puts "42 - Leave Dfu Mode (0x0020)                         (New Bezel Only)"
#KO      puts ""
#KO      puts "50 - Time Skew Test  (Takes 60 Seconds)"
#KO      puts "51 - Offset Test  How long does it take to run commands."
#KO      puts ""
#KO      puts "60 - Stop the zfs_worker (It should be running for at least 15 minutes before stopping"
#KO      puts "61 - Start the zfs_worker"
#KO      puts "62 - Stop All Services"
#KO      puts "63 - Start All Services"
#KO      puts ""
      puts "99 - Graceful Exit"
  
      puts "\nPlease choose: "
      choice = $stdin.gets.chomp
      choice = choice.to_i 
  
      if choice == 99
        break
      end
  
      @bezel_mutex.synchronize do
        case choice
        when 1
          get_identity()
        when 2
          get_version_info()
        when 3
          set_time()
        when 4
          get_time()
        when 5
          read_manufacturing_info()
        when 6
          get_time_difference()
        when 7
          puts "Invalid Choice"  # KO
#KO          sync_time()
#KO        when 10
#KO          delay = get_integer("Enter Delay in ms 0 or greater: ")
#KO          display_purple_scroll_with_delay(delay)   # 0x0001
#KO        when 11 
#KO          delay = get_integer("Enter Delay in ms 0 or greater: ")
#KO          display_yellow_scroll_with_delay(delay)   # 0x0002
#KO        when 12 
#KO          delay = get_integer("Enter Delay in ms 0 or greater: ")
#KO          display_red_scroll_with_delay(delay)      # 0x0003
#KO        when 13 
#KO          delay = get_integer("Enter Delay in ms 0 or greater: ")
#KO          display_orange_scroll_with_delay(delay)   # 0x0004
#KO        when 14
#KO          delay = get_integer("Enter Delay in ms 0 or greater: ")
#KO          display_rainbow_scroll_with_delay(delay)  # 0x0005
#KO        when 15
#KO          delay = get_integer("Enter Delay in ms 0 or greater: ")
#KO          display_flashing_blue_with_delay(delay)   # 0x0006
#KO        when 16
#KO          delay = get_integer("Enter Delay in ms 0 or greater: ")
#KO          display_pulsing_red_with_delay(delay)     # 0x0007
#KO        when 17
#KO          delay = get_integer("Enter Delay in ms 0 or greater: ")
#KO          display_rgb_cycle_with_delay(delay)       # 0x0100
        when 20
          time, beginning = get_pattern_at_inputs()
          display_purple_scroll_at(time, beginning)   # 0x0001
        when 21 
           time, beginning = get_pattern_at_inputs()
          display_yellow_scroll_at(time, beginning)   # 0x0002
        when 22 
           time, beginning = get_pattern_at_inputs()
          display_red_scroll_at(time, beginning)      # 0x0003
        when 23 
           time, beginning = get_pattern_at_inputs()
          display_orange_scroll_at(time, beginning)   # 0x0004
        when 24
           time, beginning = get_pattern_at_inputs()
          display_rainbow_scroll_at(time, beginning)  # 0x0005
        when 25
           time, beginning = get_pattern_at_inputs()
          display_flashing_blue_at(time, beginning)   # 0x0006
        when 26
           time, beginning = get_pattern_at_inputs()
          display_pulsing_red_at(time, beginning)     # 0x0007
        when 27
           time, beginning = get_pattern_at_inputs()
          display_rgb_cycle_at(time, beginning)       # 0x0100
        when 30
          get_current_pattern()
#KO        when 40
#KO         fw_file = get_string("Enter full path to FW file, or just Enter for default")
#KO          update_firmware(fw_file)
#KO        when 41
#KO          enter_dfu_boot_loader()                   # 0x0020
#KO        when 42
#KO          sn = get_string("Please enter ther Serial Numbers of the bezels, separated by commas")
#KO          serial_numbers = sn.split(",")
#KO          leave_dfu_boot_loader(serial_numbers)
#KO        when 50
#KO          call_check_time_drift
#KO        when 51
#KO          get_offset
#KO        when 60
#KO          stop_zfs_worker
#KO        when 61
#KO          start_zfs_worker
#KO        when 62
#KO          stop_all_services
#KO        when 63
#KO          start_all_services
#KO        when 80
#KO          call_failed_read
        else
          puts "Invalid Choice"
        end
      end
    end
  end
  
  def self.main
    options = {:old_bezel_devs => [], :new_bezel_devs => []}

    optparse = OptionParser.new do |opts|
      opts.banner = "Usage: #{$0} [options]"

      opts.on('-o', '--oldbezeldev', "Old Bezel Device (/dev/da2)") do |old_bezel|
        options[:old_bezel_devs] << ARGV[0]
      end

      opts.on('-n', '--newbezeldev', "New Bezel Device (/dev/cuaU0 or /dev/ttyACM0)") do |new_bezel|
        options[:new_bezel_devs] << ARGV[0]
      end

      opts.on('-h', '--help', 'Display this screen') do
        puts(opts)
        exit
      end
    end

    optparse.parse!

    if options[:old_bezel_devs].empty? && options[:new_bezel_devs].empty?
      raise "No bezels Entered"
    end

    sbt = SerialBezelTest.new(options)

    puts "Setting Bezel(s) Time to Current Time"
    sbt.bezel_mutex.synchronize do
      sbt.set_time()                                 # Set the Current Time
    end
    sleep 3
    puts "Setting Bezel(s) to Default Purple Scroll"
    sbt.bezel_mutex.synchronize do
      sbt.display_purple_scroll_at(Time.now + 3, 1)  # Set to Purple Scroll
    end
    sleep 3
    puts "Setting up Bezel Ping"
    sbt.keep_talking()  # Start keep talking thread so it does not flash red
    sleep 3

    puts "Setting up Bezel Sync"
    sbt.keep_in_sync()  # Start keep_in_insync() thread so the patterns don't get to far off.
    sleep 3

    sbt.menu            # Start the menu
    0
  end
end # SerialBezelTest
  
  
exit(SerialBezelTest::main) if $0 == __FILE__
