module Tools
  require 'logger'
  require 'thread'
  require 'find'
  
  class Common
    
    # returns the name of the started script
    #
    # +without_extension+ true to remove the extension
    def self.scriptname(without_extension = false)
      if without_extension
        File.basename($0, ".*")
      else
        File.basename($0)
      end
    end
    
    # returns the base-directory of the current script
    def self.basedir()
      File.expand_path(File.dirname($0))
    end
  end
  
  class PasswortGenerator
    NUM = ('0'..'9').to_a.freeze
    ALPHA_LOWER = ('a'..'z').to_a.freeze
    ALPHA_UPPER = ('A'..'Z').to_a.freeze
    ALPHA = (ALPHA_LOWER + ALPHA_UPPER).freeze
    ALPHANUM = (ALPHA + NUM).freeze
    SPECIAL = ((33..126).collect{|i| i.chr} - NUM - ALPHA_LOWER - ALPHA_UPPER).freeze
    VOWELS = "aeiouAEIOU".split(//).freeze
    ALL = (ALPHA + NUM + SPECIAL).freeze

    def self.generate(length, characters = ALL)
      chars = characters.dup.shuffle
      pw = ""
      0.upto(length-1){ pw << chars[rand(chars.size)] }
      return pw
    end
  end

  class OS
    private
    @@platform = nil

    public
    # constant for windows-platform
    WINDOWS = :WINDOWS
    # constant for osx-platform
    OSX = :OSX
    # constant for linux-platform
    LINUX = :LINUX
    # constant for freebsd-platform
    FREEBSD = :FREEBSD
    # constant for solaris-platform
    SOLARIS = :SOLARIS
    # constant for cygwin-platform
    CYGWIN = :CYGWIN
    # constant for unknown platform
    UNKNOWN = :UNKNOWN

    # constant including all known platforms
    PLATFORMS = [ WINDOWS, LINUX, OSX, FREEBSD, SOLARIS, CYGWIN, UNKNOWN ].freeze

    # the uname-command known from linux
    def self.uname()
      if whereis("ver.dll") and ENV['COMSPEC']
        uname = %x[ver]
      elsif command?("uname")
        uname = %x[uname -a]
      else
        uname = RUBY_PLATFORM
      end
      uname.strip
    end

    # returns the current platform
    def self.platform
      return @@platform if @@platform

      current = RUBY_PLATFORM
      current = uname() if current.casecmp("java") == 0
      current = current.downcase

      if current =~ /win32|mswin|mingw|bccwin|wince|windows/
        @@platform = WINDOWS
      elsif current =~ /darwin/
        @@platform = OSX
      elsif current =~ /freebsd/
        @@platform = FREEBSD
      elsif current =~ /solaris/
        @@platform = SOLARIS
      elsif current =~ /cygwin/
        @@platform = CYGWIN
      elsif current =~ /linux/
        @@platform = LINUX
      else
        @@platform = UNKNOWN
      end
      @@platform
    end

    # checks if platform equals the current platform
    #
    # +platform+ the platform to check
    def self.platform?(platform)
      platform().eql?(platform)
    end

    # returns true if on windows-platform
    def self.windows?()
      platform?(WINDOWS)
    end

    # returns true if on osx-platform
    def self.osx?()
      platform?(OSX)
    end

    # checks path if cmd exists and is executable
    #
    # +cmd+ the command
    def self.command?(cmd)
      return false if cmd.nil?
      return true if File.executable?(cmd)
      f = whereis(cmd)
      return (not f.nil? and File.executable?(f))
    end

    # same as command? but checks also some known extension on windows
    #
    # +cmd+ the command
    def self.command2?(cmd)
      return command?(cmd) if not windows?()
      win_ext = %w(cmd bat exe com)
      # file has already a known extension
      win_ext.each do |e|
        return command?(cmd) if cmd.end_with?(".#{e}")
      end
      # check each extension
      result = false
      win_ext.each do |e|
        result = command?("#{cmd}.#{e}")
        break if result
      end
      return result
    end

    # find the specified file in PATH
    #
    # +name+ the file to find
    def self.whereis(name)
      # split path
      paths = ENV["PATH"].split(File::PATH_SEPARATOR)
      # check each folder for file
      paths.each do |folder|
        f = File.join(folder, name)
        return f if File.exists?(f)
      end
      return nil
    end

    # returns the platform-dependend null-device
    def self.nullDevice()
      if windows?()
        return "NUL"
      else
        return "/dev/null"
      end
    end
  end

  class Tee
    # redirects output to file (uses no tee-command!)
    #
    # +logfile+ the file to write to
    # +append+ append to existing file or create a new one
    # +block+ all output inside the block will be redirected to logfile
    def self.tee(logfile, append=true)
      raise "no block given" unless block_given?
      file = File.open(logfile, append ? 'a' : 'w')
      mutex = Mutex.new
      stdout_old = $stdout.dup
      stderr_old = $stderr.dup
      stdout_r, stdout_w = IO.pipe
      stderr_r, stderr_w = IO.pipe
      t1 = Thread.new do
        while data = stdout_r.readpartial(1024) rescue nil
          mutex.synchronize do
            stdout_old.write(data)
            file.write(data)
          end
        end
        stdout_r.close
      end
      t2 = Thread.new do
        while data = stderr_r.readpartial(1024) rescue nil
          mutex.synchronize do
            stderr_old.write(data)
            file.write(data)
          end
        end
        stderr_r.close
      end
      begin
        $stdout.reopen(stdout_w)
        $stderr.reopen(stderr_w)
        yield
      ensure
        $stdout.reopen(stdout_old)
        $stderr.reopen(stderr_old)
        [stdout_w,stderr_w].each { |f| f.close rescue nil }
        t1.join
        t2.join
        [stdout_old,stderr_old,file].each { |f| f.close rescue nil}
      end
    end

    # creates the tee-command for cmd which redirects stderr to stdout and pipes the output to the given file.
    # If tee is not available nil will be returned.
    #
    # +cmd+ the command to run
    # +file+ the file to write in
    # +append+ true to append new data to file, falso to override file
    def self.command(cmd, file, append = false)
      cmdLine = cmd
      cmdLine << " 2>&1"
      if OS::windows?()
        teeCommand = "tee.exe"
      else
        teeCommand = "tee"
      end
      if OS::command?(teeCommand)
        cmdLine << " | #{teeCommand}"
        cmdLine << " -a" if append
        cmdLine << " \"#{file}\""
        return cmdLine
      end
      return nil
    end
  end
  
  class FileTool
    def self.waitfor(file, retry_count = -1, msg = nil)
      found = false
      last_time = nil
      loop = retry_count
      while !found and (loop != 0)
        puts msg if loop == retry_count and !msg.nil?
        loop -= 1
        ft = file_type(file)
        if ft.nil?
          # File does not exist currently
          # nothing to do for now
        elsif "dev".eql?(ft)
          # file is a device
          found = true
          break
        else
          # file is a file or a directory
          f_time = nil
          # find last modification-time
          f_count = 0
          Find.find(file) do |f|
            f_count += 1
            tmp = File.mtime(f)
            f_time = tmp if f_time.nil? or tmp > f_time 
          end
          # check if something has changed since last run
          if last_time.nil? or last_time < f_time
            last_time = f_time
          elsif f_count > 0
            # nothing has changed - so we are done
            found = true
            break
          end
        end
        sleep 1
      end
      return found
    end
    
    def self.file_type(input)
      return nil if not File.exist?(input)
      return "dev" if File.stat(input).blockdev? or File.stat(input).chardev?
      return "dir" if File.directory?(input) 
      return File.extname(input).downcase[1..-1]
    end

    def self.humanReadableSize(size)
      m = %w(B KB MB GB TB)
      idx = 0
      s = size
      while s.abs > 1024 and idx < (m.size-1)
        idx += 1
        s = s / 1024.0
      end
      return "%.2f %s" % [s, m[idx]]
    end

    def self.size(path)
      size = 0
      p = File.expand_path(path)
      return nil if not FileTest.exist?(p)
      if FileTest.directory?(p)
        Find.find("#{p}/") do |f|
          if !FileTest.directory?(f) and FileTest.readable?(f)
            size += (FileTest.size(f) || 0)
          end
        end
      else
        size += (FileTest.size(p) || 0) if FileTest.readable?(p) 
      end
      return size
    end
  end

  class TimeTool

    # converts the given time (HH:MM:SS) to seconds
    #
    # +time+ the time-string
    def self.timeToSeconds(time)
      return -1 if time.nil? or time.strip.empty?
      times = time.split(/:/).reverse
      seconds = 0
      for i in (0...times.length)
        seconds += times[i].to_i * (60**i)
      end
      return seconds
    end

    # converts the given seconds into a time string (HH:MM:SS)
    #
    # +seconds+ the seconds to convert
    def self.secondsToTime(seconds)
      return "unknown" if seconds.nil?
      t = seconds
      time = ""
      2.downto(0) { |i|
        tmp = t / (60**i)
        t = t - tmp * 60**i
        time = time + ":" if not time.empty?
        time = time + ("%02d" % tmp)
      }
      return time
    end
  end

  class Properties < Hash
    # load values from given file
    # +file+ the properties-file
    def load(file)
      File.open(File.expand_path(file), "r") do |reader|
        reader.read.each_line do |line|
          line.lstrip!
          line.chomp!
          next if line.empty? or line[0] == ?# or line[0] == ?=
          idx = line.index('=')
          if idx
            key = line[0..idx-1].strip
            value = line[idx + 1..-1].lstrip
          else
            key = line.strip
            value = nil
          end
          self[key] = value
        end
      end
      self
    end

    # store values from given file
    # +file+ the properties-file
    def store(file)
      File.open(File.expand_path(file), "w") do |writer|
        self.keys.sort.each do |key|
          value = self[key].to_s
          writer.puts("#{key}=#{value}")
        end
      end
      self
    end
  end

  class Loggers
    def self.console
      return @consoleLogger if @consoleLogger
      return @consoleLogger = createLogger
    end

    def self.createLogger(progname = nil, output = STDOUT)
      l = Logger.new(output)
      l.progname = progname || File.basename($0)
      l.formatter = JavaLogFormatter.new
      l.formatter.datetime_format = "%Y-%m-%d, %H:%M:%S"
      return l
    end
  end
  
  class JavaLogFormatter
    Format = "[%s] %5s -- %s: %s\n"
  
    attr_accessor :datetime_format
  
    def initialize
      @datetime_format = nil
    end
  
    def call(severity, time, progname, msg)
      Format % [format_datetime(time), severity, progname,
        msg2str(msg)]
    end
  
  private
  
    def format_datetime(time)
      if @datetime_format.nil?
        time.strftime("%Y-%m-%dT%H:%M:%S.") << "%06d " % time.usec
      else
        time.strftime(@datetime_format)
      end
    end
  
    def msg2str(msg)
      case msg
      when ::String
        msg
      when ::Exception
        "#{ msg.message } (#{ msg.class })\n" <<
          (msg.backtrace || []).join("\n")
      else
        msg.inspect
      end
    end
  end

  # global constant for default console-logger
  CON = Tools::Loggers.console()
end
