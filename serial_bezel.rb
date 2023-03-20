#!/usr/bin/env ruby
#
# Serial Bezel Class/API to control the New Bezel
# The communications is over USB Serial and uses the SerialPort and BinData gems.
# The Fw Upgrade is done by running the dfu-util command.
#
# Relevant Documentation
# https://confluence.spectralogic.com/pages/viewpage.action?spaceKey=SE&title=BPX+Bezel+API
# https://confluence.spectralogic.com/pages/viewpage.action?spaceKey=SE&title=Specification+-+Black+Pearl+X+Bezel
#
# Required Gems
#   serialport
#   bindata
# Required Utilities
#   dfu-util
#
# DFU Utils
# To leave DFU mode
# dfu-util -a 0 -s 0x08000000 -S "206C39823350" -L
#
# To Upload FW
# dfu-util -a 0 -S "206C39823350" -D [filename]
#
# To get it to work on Linux as non-root
#   sudo usermod -a -G tty keitho
#   sudo usermod -a -G dialout keitho
#
require 'bindata'
require 'serialport'
require 'logger'

if $0 == __FILE__
  $LOAD_PATH.unshift(File.expand_path('../../', __FILE__))
end

# require 'spectra_support/cmd'
# require 'spectra_support/errors'

module Spectra
  # Base Serial Bezel Class.
  # Classes that CAN never change
  #   Header
  #   IdentifyCommand
  #   IdentifyResponse
  #   ReadVersionInfoCommand
  #   ReadVersionInfoResponse

  class SerialBezel
    class StartWordError < StandardError
    end
  
    class ChecksumsDoNotMatch < StandardError
    end
  
    class CmdFailed < StandardError
    end

    # The Current version of the Firmware File in this gem that all bezels should
    # be updated to.  Must match the version in bezel/firmware. When the
    # actual FW file is updated this needs to be updated as well.
    FIRMWARE_VERSION = "1_0_1_0"

    # API Version
    API_VERSION = 0   # Valid For All Bezel API's
  
    # Return Code Can Never Change Only added to.
    RETURN_CODES = { 0 => "OK",
                     1 => "Unknown Command",
                     2 => "Command Not Implemented",
                     3 => "Wrong Argument Count",
                     4 => "Wrong argument value (one of the argument values is not correct)",
                     5 => "Device busy or not ready",
                     6 => "Failed to execute the command",
                     7 => "Command is not properly encoded",
                     8 => "Bad checksum" }
  
    # Patterns Should Never Change, only added to.
    NO_LIGHT       = 0x0000
    PURPLE_SCROLL  = 0x0001
    YELLOW_SCROLL  = 0x0002
    RED_SCROLL     = 0x0003
    ORANGE_SCROLL  = 0x0004
    RAINBOW_SCROLL = 0x0005
    FLASHING_BLUE  = 0x0006
    PULSING_RED    = 0x0007
    RGB_CYCLE      = 0x0100

    # Hash to Map Patterns to Human Readable
    PATTERNS = { NO_LIGHT       => "NO LIGHT",
                 PURPLE_SCROLL  => "PURPLE SCROLL",
                 YELLOW_SCROLL  => "YELLOW SCROLL",
                 RED_SCROLL     => "RED SCROLL",
                 ORANGE_SCROLL  => "ORANGE SCROLL",
                 RAINBOW_SCROLL => "RAINBOW SCROLL",
                 FLASHING_BLUE  => "FLASHING BLUE",
                 PULSING_RED    => "PULSING RED",
                 RGB_CYCLE      => "RGB CYCLE" }
  
    # OpCodes That Can Never Change.
    IDENTIFY      = 0x0000  # Identify Device
    VERSION_INFO  = 0x0001  # Version Information

    # Can Never Change, only added to.
    DISPLAY_PATTERN_AT_TIME    = 0x0002  # Display Pattern at Specified Time
    DISPLAY_PATTERN_WITH_DELAY = 0x0003  # Dipllay Patter with Delay
    GET_TIME                   = 0x0004  # Get Device Time is ms
    SET_TIME                   = 0x0005  # Set Device Time in ms
    READ_MANUFACTURING_INFO    = 0x0006  # Read Manufacturing Information
    GET_CURRENT_PATTERN        = 0x0007  # Get Current Pattern being displayed
    ENTER_DFU_BOOTLOADER       = 0x0020  # Enter DFU Bootloader.
  
    # Every Command/Response mus begin with a StartWord can NEVER change.
    START_BYTE = 0xAA
    START_WORD = 0xAAAA

    # DFU Utility
    DFU_UTIL_CMD = "/usr/local/bin/dfu-util"
  
    attr_reader   :dev
    attr_reader   :ser      # SerialPort Object
    attr_reader   :logger
  
    def initialize(dev, logger = Logger.new(STDOUT))
      @dev    = dev
      @ser    = nil
      @logger = logger
    end

    public

    # Returns the version of the current firmware file contained in the gem, with
    # underscores converted to dots "."
    def self.current_firmware_version
      FIRMWARE_VERSION.gsub("_", ".")
    end

    # Returns the name and location of the current Firmware file.
    def self.current_firmware_file
      File.dirname(__FILE__) + "/bezel/firmware/#{FIRMWARE_VERSION}.bzl"
    end

    # map_status
    # Human Readable String of Status.
    def map_status(status)
      logger.debug("#{__method__}:")
      RETURN_CODES[status]
    end
  
    # map_pattern
    # Human Readable String of Pattern
    def map_pattern(pattern)
      logger.debug("#{__method__}:")
      PATTERNS[pattern]
    end
  
    # check_status
    # Validates an OK status, and logs things.
    def check_status(status)
      logger.debug("#{__method__}:")
      logger.debug("Response Status: #{map_status(status)}")
      return true if status == 0
      false
    end
  
    # fletcher16
    # Fletcher16 the buffer
    # Input
    #   buf - Array - String Array of the buffer
    # Return
    #   checksum - Integer - Fletcher16 checksum
    def fletcher16(buf)
      logger.debug("#{__method__}:")
      sum1 = 0xff
      sum2 = 0xff
      i = 0
      len = buf.length
      while len > 0
          tlen = len > 20 ? 20 : len
          len -= tlen
          loop do
              sum2 += sum1 += buf[i]
              i += 1
              tlen -= 1
              break if tlen <= 0
          end
          sum1 = (sum1 & 0xff) + (sum1 >> 8)
          sum2 = (sum2 & 0xff) + (sum2 >> 8)
      end
      sum1 = (sum1 & 0xff) + (sum1 >> 8)
      sum2 = (sum2 & 0xff) + (sum2 >> 8)
      cs = sum2  << 8 | sum1
      logger.debug("#{__method__}: Calculated Checksum: 0x#{cs.to_s(16).rjust(2, '0')} sum1: 0x#{sum1.to_s(16).rjust(2, '0')}, sum2: 0x#{sum2.to_s(16).rjust(2, '0')}")
  
      cs
    end

    # checksums_equal?
    # Validates the checksums, if not equal logs the error.
    def checksums_equal?(header, calculated, sent)
      logger.debug("#{__method__}:")
      if calculated != sent 
        msg = "#{__method__}: Calculated Checksum 0x#{calculated.to_i.to_s(16)} (#{calculated}) does not match Sent Checksum 0x#{sent.to_i.to_s(16)} (#{sent})"
        logger.warn(msg)
        tmp_data = ""
        header.each {|i| tmp_data += "0x#{i.to_s(16)} "}
        logger.warn("#{__method__}: #{tmp_data}")
        return false
      end
      true
    end

    # convert_version_to_string.
    # The Version is 4 bytes representing Major.Minor.Patch.Build
    # Input
    #   version - Integer - Integer representation of version
    # Return
    #   version - String  - String representation of version "Major.Minor.Patch.Build"
    def self.convert_version_to_string(version)
      major = (version & 0xFF)
      minor = ((version >> 8)  & 0xFF)
      patch = ((version >> 16) & 0xFF)
      build = ((version >> 24) & 0xFF)
      "#{major}.#{minor}.#{patch}.#{build}"
    end

    # run_command
    # Run block x amount of times, just in case the Serial Communications is
    # flaky.
    # Input
    #   retry_count - The number of times to retyr
    #   block       - The block of code to run
    def run_command(retry_count = 5, &block)
      logger.debug("#{__method__}:")
      attempts ||= 1
      begin
        logger.info("Attempt: #{attempts}")
        block.call
      rescue StandardError => se
        logger.error("Error: #{se.message}")
        if (attempts += 1) <= retry_count
          logger.info("<retrying>")
          sleep(0.25)
          retry
        end
        logger.error("Retry attempts Exceeded. Moving on.")
        raise se
      end
    end
  
    # get_offset
    # Gets the Time offset from running commands
    # Used when setting the time.
    # Input
    #   iterations - Integer - Number of iterations to run to determine offset
    # Return
    #   write_offset - Float - Calculated Write Offset
    #   read_offset  - Float - Calculated Read Offset
    #   offset       - Float - Total Offset
    def get_offset(iterations = 60)
      calculate_offset(iterations)
    end

    # get_identity
    # Gets the API_VERSION and product.
    # Input
    #   None
    # Return
    #   api_version - Integer - API Version of the device
    #   product     - String  - Product Identify ("SPECTRA BEZEL 02")
    # Exceptions
    #   CmdFailed
    def get_identity()
      logger.debug("#{__method__}:")
      run_command(5) do
        cmd = IdentifyCommand.new()
        cmd.set_values()
        write(cmd)
  
        response = read(IdentifyResponse)
        unless (check_status(response.header.status))
          msg = "Identify Command Failed with Status: #{response.header.status} (#{map_status(response.header.status)})"
          logger.error("#{__method__}: #{msg}")
          raise CmdFailed, msg
        end
  
        response.parse_response()
      end
    end

    # get_version_info
    # Gets the Serial Number, Firmware Version, Hardware Rev and BootLoader version.
    # Input
    #   None
    # Return
    #   serial_number      - string  - Serial Number of the device
    #   firmware_version   - string  - Firmware Version "Major.Minor.Patch.Build"
    #   reserved           - Integer - Reserved
    #   hardware revision  - Integer - Hardware Revision
    #   bootloader_version - string  - Bootloader Version "Major.Minor.Patch.Build"
    #
    # Exceptions
    #   CmdFailed
    def get_version_info
      run_command(5) do
        logger.debug("#{__method__}:")
        cmd = ReadVersionInfoCommand.new()
        cmd.set_values()
        write(cmd)
  
        response = read(ReadVersionInfoResponse)
        unless (check_status(response.header.status))
          msg = "Version Info Command Failed with Status: #{response.header.status} (#{map_status(response.header.status)})"
          logger.error("#{__method__}: #{msg}")
          raise CmdFailed, msg
        end
  
        response.parse_response()
      end
    end

    # Display Commands at Specified Time Helper Method
    # Input
    #   start_time - Integer - Start Time in ms
    #   beginning  - Integer - Non zero start pattern at beginning
    # Return
    #   None
    def display_purple_scroll_at(start_time, beginning)
      logger.debug("#{__method__}:")
      display_pattern_at(PURPLE_SCROLL, start_time, beginning)
    end
  
    def display_yellow_scroll_at(start_time, beginning)
      logger.debug("#{__method__}:")
      display_pattern_at(YELLOW_SCROLL, start_time, beginning)
    end
  
    def display_red_scroll_at(start_time, beginning)
      logger.debug("#{__method__}:")
      display_pattern_at(RED_SCROLL, start_time, beginning)
    end
  
    def display_orange_scroll_at(start_time, beginning)
      logger.debug("#{__method__}:")
      display_pattern_at(ORANGE_SCROLL, start_time, beginning)
    end
  
    def display_rainbow_scroll_at(start_time, beginning)
      logger.debug("#{__method__}:")
      display_pattern_at(RAINBOW_SCROLL, start_time, beginning)
    end
  
    def display_flashing_blue_at(start_time, beginning)
      logger.debug("#{__method__}:")
      display_pattern_at(FLASHING_BLUE, start_time, beginning)
    end
  
    def display_pulsing_red_at(start_time, beginning)
      logger.debug("#{__method__}:")
      display_pattern_at(PULSING_RED, start_time, beginning)
    end
  
    def display_rgb_cycle_at(start_time, beginning)
      logger.debug("#{__method__}:")
      display_pattern_at(RGB_CYCLE, start_time, beginning)
    end

    # Display Commands With Delay Helper Method
    # Input
    #   delay - Integer - Delay in ms
    # Return
    #   None
    def display_purple_scroll_with_delay(delay)
      logger.debug("#{__method__}:")
      display_pattern_with_delay(PURPLE_SCROLL, delay)
    end
  
    def display_yellow_scroll_with_delay(delay)
      logger.debug("#{__method__}:")
      display_pattern_with_delay(YELLOW_SCROLL, delay)
    end
  
    def display_red_scroll_with_delay(delay)
      logger.debug("#{__method__}:")
      display_pattern_with_delay(RED_SCROLL, delay)
    end
  
    def display_orange_scroll_with_delay(delay)
      logger.debug("#{__method__}:")
      display_pattern_with_delay(ORANGE_SCROLL, delay)
    end
  
    def display_rainbow_scroll_with_delay(delay)
      logger.debug("#{__method__}:")
      display_pattern_with_delay(RAINBOW_SCROLL, delay)
    end
  
    def display_flashing_blue_with_delay(delay)
      logger.debug("#{__method__}:")
      display_pattern_with_delay(FLASHING_BLUE, delay)
    end
  
    def display_pulsing_red_with_delay(delay)
      logger.debug("#{__method__}:")
      display_pattern_with_delay(PULSING_RED, delay)
    end
  
    def display_rgb_cycle_with_delay(delay)
      logger.debug("#{__method__}:")
      display_pattern_with_delay(RGB_CYCLE, delay)
    end

    # get_time
    # Args:
    #   None
    # Return
    #   time - Integer - Time in ms.
    def get_time()
      logger.debug("#{__method__}:")
      # Get The API version first.
      api_version, product = get_identity()
  
      run_command(5) do
        cmd = eval("GetTimeCommandV#{api_version}").new()
        cmd.set_values()
        write(cmd)
  
        response = read(eval("GetTimeResponseV#{api_version}"))
        unless (check_status(response.header.status))
          msg = "Get Time Command Failed with Status: #{response.header.status} (#{map_status(response.header.status)})"
          logger.error("#{__method__}: #{msg}")
          raise CmdFailed, msg
        end
  
        response.parse_response()
      end
    end

    # set_time
    # Args:
    #   time - Integer - Time in ms, if nil set to Current Time.
    # Return
    #   None
    def set_time(time = nil)
      logger.debug("#{__method__}:")
      # Get The API version first.
      api_version, product = get_identity()
  
      run_command(5) do
        cmd = eval("SetTimeCommandV#{api_version}").new()

        if time.nil?
          w_offset, r_offset, offset = calculate_offset()
          time = ((Time.now().to_f * 1000).to_i)
          time = time + (offset * 1000).round(0)
        end
        cmd.set_values(time)
        write(cmd)
  
        response = read(eval("SetTimeResponseV#{api_version}"))
        unless (check_status(response.header.status))
          msg = "Set Time Command Failed with Status: #{response.header.status} (#{map_status(response.header.status)})"
          logger.error("#{__method__}: #{msg}")
          raise CmdFailed, msg
        end
  
        response.parse_response
      end
    end

    
    # read_manufacturing_info
    # Args:
    #   None
    # Return
    #   fru_serial_number - string - The FRU Serial Number
    #   ec_number         - uint16 - The EC Number
    # Read the Manufacturing Info (for ASL only)
    def read_manufacturing_info()
      logger.debug("#{__method__}:")
      # Get The API version first.
      api_version, product = get_identity()
  
      run_command(5) do
        cmd = eval("ReadManufacturingInfoCommandV#{api_version}").new()
        cmd.set_values()
        write(cmd)
  
        response = read(eval("ReadManufacturingInfoResponseV#{api_version}"))
        unless (check_status(response.header.status))
          msg = "Read Manufacturing Info Command Failed with Status: #{response.header.status} (#{map_status(response.header.status)})"
          logger.error("#{__method__}: #{msg}")
          raise CmdFailed, msg
        end
  
        response.parse_response
      end
    end

    # get_current_pattern
    # Args:
    #   None
    # Return
    #   pattern - Integer - Integer representation of the current pattern
    def get_current_pattern()
      logger.debug("#{__method__}:")
      # Get The API version first.
      api_version, product = get_identity()

      run_command(5) do
        cmd = eval("GetCurrentPatternCommandV#{api_version}").new()
        cmd.set_values()
        write(cmd)
  
        response = read(eval("GetCurrentPatternResponseV#{api_version}"))
        unless (check_status(response.header.status))
          msg = "Get Current Pattern Command Failed with Status: #{response.header.status} (#{map_status(response.header.status)})"
          logger.error("#{__method__}: #{msg}")
          raise CmdFailed, msg
        end
  
        response.parse_response
      end
    end
  
    # update_firmware
    # Args:
    #   serial_number - Serial Number of bezel.  The dfu command needs it.
    #   fw_file       - Full path of Firmware file (optional), for testing.
    # Return:
    #   None
    #
    #   Will update the FW with the file specified, or default to the version
    #   contained in the GEM.
    #
    # To Update the FW the procedure is:
    #    1. enter DFU mode
    #    2. Upload the FW
    #    3. Leave DFU Mode - Currently does not return 0 when successful

    def update_firmware(serial_number, fw_file = nil)
      logger.debug("#{__method__}:")
      begin
        enter_dfu_boot_loader()
        update_fw(serial_number, fw_file)
      ensure
        leave_dfu_boot_loader(serial_number)
      end
      nil
    end

    private
    ################
    # BASE CLASSES #
    ################

    # StartWord Class for writing. Can Never Change
    class StartWord < BinData::Record
      endian :little
  
      uint16 :start_word
    end
  
    # Checksum Class for writing. Can Never Change
    class Checksum < BinData::Record
      endian :little
  
      uint16 :checksum
    end
  
    # Header Class Can Never Change.
    class Header < BinData::Record
      endian :little
  
      uint16 :api_version
      uint16 :command
      uint16 :status
      uint16 :reserved1
      uint16 :reserved2
      uint16 :reserved3
      uint16 :len
  
      # Would like to do this in the Initialize method of each Command but BinData does not allow it.
      def populate(api_version, opcode, length)
        self.api_version = api_version
        self.command     = opcode
        self.status      = 0x0000
        self.reserved1   = 0x0000
        self.reserved2   = 0x0000
        self.reserved3   = 0x0000
        self.len         = length
      end
    end
  
    # Identify Command Class Can Never Change.
    class IdentifyCommand < BinData::Record
      API_VERSION = 0
      endian :little
  
      Header :header
  
      def set_values
        self.header.populate(SerialBezel::API_VERSION, SerialBezel::IDENTIFY, 0x0000)
      end
    end
  
    # IdentifyResponse Class Can Never Change
    class IdentifyResponse < BinData::Record
      API_VERSION = 0
      PRODUCT_LENGTH = 16
      endian :little
  
      Header :header
      string :product, :read_length => PRODUCT_LENGTH
  
      # Parses the response.
      def parse_response()
        return header.api_version, product
      end
    end
  
    # ReadVersionInfoCommand Class Can Never Change.
    class ReadVersionInfoCommand < BinData::Record
      API_VERSION = 0
      endian :little
  
      Header :header
  
      # Need this b/c BinData does not allow me to have an initialize method.
      def set_values
        self.header.populate(SerialBezel::API_VERSION, SerialBezel::VERSION_INFO, 0x0000)
      end
    end
  
    # ReadVersionInfoResponse Class Can Never Change
    class ReadVersionInfoResponse < BinData::Record
      API_VERSION = 0
      endian :little
  
      Header :header
  
      uint16 :serial1  # First  Part of Serial Number
      uint16 :serial2  # Second Part of Serial Number
      uint16 :serial3  # Third  Part of Serial Number
      uint32 :fw       # Firmware Version
      uint16 :reserved # Reserved
      uint16 :hw       # Hardware Version
      uint32 :bl       # Boot Loader Version
  
      # Parses the Response
      def parse_response
        serial_number = serial1.to_i.to_s(16).upcase + serial2.to_i.to_s(16).upcase + serial3.to_i.to_s(16).upcase
        firmware      = SerialBezel::convert_version_to_string(fw)
        reserved      = reserved
        hardware      = hw
        boot_loader   = SerialBezel::convert_version_to_string(bl)
  
        return serial_number.upcase, firmware, reserved, hardware, boot_loader
      end
    end

    ##################
    # Common Methods #
    ##################

    # open
    # Open the port and set some default values.
    def open(baud = 115200, data_bits = 8, stop_bits = 1, parity = SerialPort::NONE)
      logger.debug("#{__method__}:")
      @ser = SerialPort.new(@dev, baud, data_bits, stop_bits, parity)
      @ser.binmode
      @ser.set_encoding("BINARY")
      @ser.read_timeout = 3000
    end
   
    # close
    # Close the port
    def close
      logger.debug("#{__method__}:")
      @ser.close() unless @ser.closed?
    end
  
    # write
    # Opens the Port b/c we always initiate comm.
    # Attaches StartWord to beginning and Checksum to the end.
    # Flushes input and output b/c we don't want stuff on the wire.
    # Input
    #   command - CommandClass - Command Ojbect
    # Return
    #   num - Integer - Number of bytes written. 
    def write(command)
      logger.debug("#{__method__}:")
      open()
      @ser.flush_input
      @ser.flush_output
  
      # All writes must start with the START_WORD
      sw = StartWord.new
      sw.start_word = START_WORD
  
      # Generate the checksum
      payload = []
      command.to_binary_s.each_byte {|b| payload << b}
      cs = Checksum.new()
      cs.checksum = fletcher16(payload)
  
      # For debugging only to print what was sent over the wire.
      data = ""
      sw.to_binary_s.each_byte      {|b| data += "0x#{b.to_s(16)} "}
      command.to_binary_s.each_byte {|b| data += "0x#{b.to_s(16)} "}
      cs.to_binary_s.each_byte      {|b| data += "0x#{b.to_s(16)} "}
      logger.debug("#{__method__}: Writing Data: #{data}")
      logger.debug("#{__method__}: Writing: #{sw} #{command} #{cs}")
  
      # Send StartWord, Payload, Checksum
      num = @ser.write(sw.to_binary_s + command.to_binary_s + cs.to_binary_s)
      logger.debug("#{__method__}: Wrote #{num} bytes.")
      num
    end
  
    # read
    # Assumes Open Serial Port b/c you must write something to Read from it.
    # closes when done.
    # Input
    #   klass - ResponsClass - Response Class to read response into.
    # Return
    #   response - ResponseClassObject - Response
    def read(klass)
      logger.debug("#{__method__}:")
      logger.debug("#{__method__}: Reading Data from pipe.")
      read_start_word()
  
      # Read Response.
      response = klass.read(@ser)
      # For debugging only to print what was sent over the wire.
      data = ""
      response.to_binary_s.each_byte      {|b| data += "0x#{b.to_s(16)} "}
      logger.debug("#{__method__}: Read Response Raw: #{data}")
      logger.debug("#{__method__}: Read Response: #{response}")
  
      # Read Checksum
      logger.debug("#{__method__}: Reading Checksum")
      response_checksum = Checksum.read(@ser)
      logger.debug("#{__method__}: Read Checksum: #{response_checksum}")
  
      # Calculate and Check Checksum
      data = []
      response.to_binary_s.each_byte {|b| data << b}
      calculated_checksum = fletcher16(data)
  
      unless checksums_equal?(data, calculated_checksum, response_checksum.checksum)
        raise ChecksumsDoNotMatch
      end
  
      response
    ensure
      close()
    end

    # Read until we encounter two 0xAA is a row, or we fail to read.
    # Timeout
    def read_start_word
      logger.debug("#{__method__}:")
      timeout = 5
      start_word_count = 0
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      loop do
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        if ((now - start_time) >= timeout)
          msg = "Failed to read Start Word, #{timeout} second timeout reached."
          logger.error("#{__method__}: #{msg}")
          raise StartWordError, msg
        end
        start_word = @ser.read(1)
        if start_word.nil?
          logger.error("#{__method__}: Nothing on the wire.")
          sleep 0.25
          next
        end
        # Got something
        if start_word.unpack("C")[0] == START_BYTE
          start_word_count += 1
          logger.debug("#{__method__}: Found Start Word #{start_word_count}")
          return true if start_word_count == 2
         else # Reset to 0 Got some junk.
           logger.debug("#{__method__}: Got Junk, resetting count to 0.")
           start_word_count = 0
         end
      end
    rescue Exception => e
      msg = "Failed to read Start Word, #{e.message}"
      logger.error("#{__method__}: #{msg}")
      raise StartWordError, msg 
    end

    # Classes and Methods, that may change depending upon the API Version, so the Versioned SUB CLASSES will have to 
    # change accordingly.
 
    ######################
    # DISPLAY PATTERN AT #
    ######################

    # DisplayPatternAtCommandV1 API Version V1
    class DisplayPatternAtCommandV1 < BinData::Record
      API_VERSION = 1
      endian :little
  
      Header :header
  
      uint16 :pattern    # Pattern Number
      uint64 :start_time # Time in ms
      uint16 :beginning  # Start at Beginning or at next position.
  
      # Need this b/c BinData does not allow me to have an initialize method.
      def set_values(pattern, time, beginning)
        self.header.populate(SerialBezel::API_VERSION, SerialBezel::DISPLAY_PATTERN_AT_TIME, 0x000C)
        self.pattern    = pattern
        self.start_time = time
        self.beginning  = beginning
      end
    end
  
    # DisplayPatternAtResponseV1 API Version V1
    class DisplayPatternAtResponseV1 < BinData::Record
      API_VERSION = 1
      endian :little
  
      Header :header
  
      # Parse the Response
      def parse_response
        return nil
      end
    end
  
    ##############################
    # DISPLAY PATTERN WITH DELAY #
    ##############################
  
    # DisplayPatternWithDelayCommandV1 API Version V1
    class DisplayPatternWithDelayCommandV1 < BinData::Record
      API_VERSION = 1
      endian :little
  
      Header :header
  
      uint16 :pattern # Pattern Number
      uint16 :delay   # Delay in ms
  
      # Need this b/c BinData does not allow me to have an initialize method.
      def set_values(pattern, delay)
        self.header.populate(SerialBezel::API_VERSION, SerialBezel::DISPLAY_PATTERN_WITH_DELAY, 0x0004)
        self.pattern    = pattern
        self.delay      = delay
      end
    end
  
    # DisplayPatternWithDelayResponseV1 API Version V1
    class DisplayPatternWithDelayResponseV1 < BinData::Record
      API_VERSION = 1
      endian :little
  
      Header :header
  
      def parse_response
        return nil
      end
    end
  
    ############
    # GET TIME #
    ############
  
    # GetTimeCommandV1 API Version V1
    class GetTimeCommandV1 < BinData::Record
      API_VERSION = 1
      endian :little
  
      Header :header
  
      # Need this b/c BinData does not allow me to have an initialize method.
      def set_values()
        self.header.populate(SerialBezel::API_VERSION, SerialBezel::GET_TIME, 0x0000)
      end
    end
  
    # GetTimeResponseV1 API Version V1
    class GetTimeResponseV1 < BinData::Record
      API_VERSION = 1
      endian :little
  
      Header :header
  
      uint64 :time  # Time in ms
  
      def parse_response
        return time
      end
    end
  
    ############
    # SET TIME #
    ############
  
    # SetTimeCommandV1 API Version V1
    class SetTimeCommandV1 < BinData::Record
      API_VERSION = 1
      endian :little
  
      Header :header
  
      uint64 :time  # Time in ms
  
      # Need this b/c BinData does not allow me to have an initialize method.
      def set_values(time)
        self.header.populate(SerialBezel::API_VERSION, SerialBezel::SET_TIME, 0x0008)
        self.time = time
      end
    end
  
    # SetTimeResponseV1 API Version V1
    class SetTimeResponseV1 < BinData::Record
      API_VERSION = 1
      endian :little
  
      Header :header
  
      def parse_response
        return nil
      end
    end
  
    ###########################
    # READ MANUFACTURING INFO #
    ###########################
  
    # ReadManufacturingInfoCommandV1 API Version V1
    class ReadManufacturingInfoCommandV1 < BinData::Record
      API_VERSION = 1
      endian :little
  
      Header :header
  
      # Need this b/c BinData does not allow me to have an initialize method.
      def set_values()
        self.header.populate(SerialBezel::API_VERSION, SerialBezel::READ_MANUFACTURING_INFO, 0x0000)
      end
    end
  
    # ReadManufacturingInfoResponseV1 API Version V1
    class ReadManufacturingInfoResponseV1 < BinData::Record
      API_VERSION = 1
      FRU_SERIAL_NUMBER_LENGTH = 10
      endian :little
  
      Header :header
  
      string :fru_serial_number, :read_length => FRU_SERIAL_NUMBER_LENGTH
      uint16 :ec_number
  
      def parse_response
        return fru_serial_number, ec_number
      end
    end
  
    #######################
    # GET CURRENT PATTERN #
    #######################
  
    # GetCurrentPatternCommandV1 API Version V1
    class GetCurrentPatternCommandV1 < BinData::Record
      API_VERSION = 1
      endian :little
  
      Header :header
  
      # Need this b/c BinData does not allow me to have an initialize method.
      def set_values()
        self.header.populate(SerialBezel::API_VERSION, SerialBezel::GET_CURRENT_PATTERN, 0x0000)
      end
    end
  
    # GetCurrentPatternResponseV1 API Version V1
    class GetCurrentPatternResponseV1 < BinData::Record
      API_VERSION = 1
      endian :little
  
      Header :header
  
      uint16 :pattern
  
      def parse_response
        return pattern
      end
    end
  
    ########################
    # ENTER DFU BOOTLOADER #
    ########################
    
    # Note: When you enter DFU BootLoader the USB Serial Comm port goes away and you can no longer talk to the bezel
    # until you leave the DFU Bootloader using the 'dfu-util -a 0 -s 0x08000000 -S "206C39823350" -L' command
  
    # EnterDFUBootLoaderCommandV1 API Version V1
    class EnterDFUBootLoaderCommandV1 < BinData::Record
      API_VERSION = 1
      endian :little
  
      Header :header
  
      # Need this b/c BinData does not allow me to have an initialize method.
      def set_values()
        self.header.populate(SerialBezel::API_VERSION, SerialBezel::ENTER_DFU_BOOTLOADER, 0x0000)
      end
    end
  
    # EnterDFUBoolLoaderResponseV1 API Version V1
    class EnterDFUBootLoaderResponseV1 < BinData::Record
      API_VERSION = 1
      endian :little
  
      Header :header
  
      def parse_response
        return nil
      end
    end
 
    # display_pattern_at(pattern, time, beginning)
    # Args:
    #   pattern    - uint16 - Pattern Number
    #   start_time - uint32 - Time in ms
    #   beginning  - uint16 - 0        - Start pattern at next_pos
    #                         non-zero - Start Pattern at beginning
    def display_pattern_at(pattern, start_time, beginning)
      logger.debug("#{__method__}:")
      # Get The API version first.
      api_version, product = get_identity()
     
      run_command(5) do
        cmd = eval("DisplayPatternAtCommandV#{api_version}").new()
        cmd.set_values(pattern, start_time, beginning)
        write(cmd)
  
        response = read(eval("DisplayPatternAtResponseV#{api_version}"))
  
        unless (check_status(response.header.status))
          msg = "Display Pattern At Command Failed with Status: #{response.header.status} (#{map_status(response.header.status)})"
          logger.error("#{__method__}: #{msg}")
          raise CmdFailed, msg
        end
  
        response.parse_response
      end
    end
  
    # display_pattern_with_delay(pattern, delay)
    # Args:
    #   pattern - uint16 - Pattern Number
    #   delay   - uint16 - Time in ms
    def display_pattern_with_delay(pattern, delay)
      logger.debug("#{__method__}:")
      # Get The API version first.
      api_version, product = get_identity()
     
      run_command(5) do
        cmd = eval("DisplayPatternWithDelayCommandV#{api_version}").new()
        cmd.set_values(pattern, delay)
        write(cmd)
  
        response = read(eval("DisplayPatternWithDelayResponseV#{api_version}"))
  
        unless (check_status(response.header.status))
          msg = "Display Pattern With Delay Command Failed with Status: #{response.header.status} (#{map_status(response.header.status)})"
          logger.error("#{__method__}: #{msg}")
          raise CmdFailed, msg
        end
  
        response.parse_response
      end
    end
  
    # enter_dfu_boot_loader
    # Args:
    #   None
    # Return
    #   None
    def enter_dfu_boot_loader()
      logger.debug("#{__method__}:")
      # Get The API version first.
      api_version, product = get_identity()
  
      run_command(5) do
        cmd = eval("EnterDFUBootLoaderCommandV#{api_version}").new()
        cmd.set_values()
        write(cmd)
  
        response = read(eval("EnterDFUBootLoaderResponseV#{api_version}"))
        unless (check_status(response.header.status))
          msg = "Enter DFU Boot Loader Command Failed with Status: " \
               "#{response.header.status} (#{map_status(response.header.status)})"
          logger.error("#{__method__}: #{msg}")
          raise CmdFailed, msg
        end
        sleep 3
  
        response.parse_response
      end
    end
  
    # Calculates the time offest in sending commands by sending the same command
    # over and over.
    # Args
    #   Integer - Iterations - Number of iterations
    # Return
    #   Integer - Write Offset
    #   Integer - Read Offset
    #   Integer - Total Offset
    def calculate_offset(iterations = 60)
      logger.debug("#{__method__}:")
      w_total = 0
      r_total = 0
  
      command = IdentifyCommand.new()
      command.set_values()
  
      # All writes must start with the START_WORD
      sw = StartWord.new
      sw.start_word = START_WORD
  
      # Generate the checksum
      payload = []
      command.to_binary_s.each_byte {|b| payload << b}
      cs = Checksum.new()
      cs.checksum = fletcher16(payload)
  
      (0...iterations).each do
        open()
        @ser.flush_input
        @ser.flush_output
  
        t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        x = @ser.write(sw.to_binary_s + command.to_binary_s + cs.to_binary_s)
        t2 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        IdentifyCommand.read(@ser)
        t3 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        w_total += (t2 - t1) 
        r_total += (t3 - t2) 
        @ser.flush_input
        @ser.flush_output
        @ser.close() unless @ser.closed?
      end
      w_offset = (w_total / iterations)
      r_offset = (r_total / iterations)
      offset = w_offset + r_offset
      logger.debug("#{__method__}: Write Offset: #{w_offset} Read Offset: #{r_offset} Total Offset: #{offset}")
      return w_offset, r_offset, offset
    end

    # update_fw
    # Args:
    #   serial_number - Serial Number of bezel.  The dfu command needs it.
    #   fw_file       - Full path of Firmware file (optional), for testing.
    # Return:
    #   None
    #
    #   Will update the FW with the file specified, or default to the version
    #   contained in the GEM.
    #
    # To update Firmware
    #   dfu-util -a 0 -S "206C39823350" -D <filename>
    #
    # As of 29-Apr-2021, the latest Firmware can be found at
    # http://vm-tape-jenkins.sldomain.com:8080/vm-tape-jenkins/job/BPX-Bezel/job/main/
    # The .bzl file is the Application .dfu file, and the .bzb file is the
    # bootloader .dfu file that is loaded by manufacturing.
    #
    def update_fw(serial_number, fw_file = nil)
      logger.debug("#{__method__}:")

      if fw_file.nil? || fw_file.empty?
        fw_file = Spectra::SerialBezel::current_firmware_file()
      end
      logger.info("#{__method__}: Updating Firmware on Serial Bezel " \
                        "(#{self.dev}) SN: #{serial_number} with #{fw_file}")
      update_cmd = [DFU_UTIL_CMD, "-a", 0, "-S", serial_number, "-D", fw_file]
      Cmd.run!(update_cmd)
      logger.info("#{__method__}: Successfully Updated Firmware on Serial " \
                    "Bezel (#{self.dev}) SN: #{serial_number} with #{fw_file}")
      sleep 3
      nil
    end

    # leave_dfu_boot_loader
    # Args:
    #   serial_number - Serial Number of bezel.  The dfu command needs it.
    # Return:
    #   None
    #
    # To leave DFU mode
    #   dfu-util -a 0 -s 0x08000000 -S "206C39823350" -L
    def leave_dfu_boot_loader(serial_number)
      logger.debug("#{__method__}:")
      logger.info("#{__method__}: Leaving Bootloader on Serial Bezel " \
                                         "(#{self.dev}) SN: #{serial_number}")
      leave_cmd  = [DFU_UTIL_CMD, "-a", 0, "-s", "0x08000000", "-S",
                                                         serial_number, "-L"]
      c = Cmd.run(leave_cmd)
      # The leave bootloader command currently returns a status of 74, even
      # though it worked.  This is b/c ST Micro strayed from the dfu-util
      # spec and no longer pauses a little bit for dfu-util to query it.
      # If this ever gets fixed, then we can use Cmd.run! and not have to
      # manually raise an exception.
      unless [0, 74].include?(c.exitstatus)
        msg = "Failed to Leave DFU Bootloader. #{c.err}"
        logger.error("#{__method__}: #{msg}")
        raise CmdFailed, msg
      end
      logger.info("#{__method__}: Left Bootloader on Serial Bezel " \
                     "(#{self.dev}) SN: #{serial_number}")
      sleep 3
      nil
    end
  
  end # SerialBezel
end # Module Spectra
