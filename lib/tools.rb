module Tools
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
  
  def self.getTool(name, executable)
    platform = OS::platform().to_s.downcase
    path = File.join(File.expand_path("tools"), name, platform)
    cmd = File.join(path, executable)
    return cmd if OS::command?(cmd)

    if OS::windows?()
      %w(bat cmd exe com).each do |e|
        wincmd = cmd + "." + e
        return wincmd if OS::command?(wincmd)
      end
    end

    return nil
  end
  
  class Tee
    # creates the tee-command for cmd
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
      end
      return cmdLine
    end
    
    # runs cmd with tee
    #
    # +cmd+ the command to run
    # +file+ the file to write in
    # +append+ true to append new data to file, falso to override file
    def self.run(cmd, file, append = false)
      cmdLine = teeCommand(cmd,file,append)
      %x[#{cmdLine}]
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

  class Log
    DEBUG = 8
    INFO = 4
    WARNING = 2
    ERROR = 1
    ALL = 999

    @@level = ALL

    def self.level=(l)
      @@level = l
    end
    
    def self.level
      @@level
    end

    def self.debug(msg)
      log(DEBUG, msg)
    end  
    def self.info(msg)
      log(INFO, msg)      
    end
    def self.warn(msg)
      log(WARNING, msg)
    end
    def self.error(msg)
      log(ERROR, msg)
    end
    private
    LEVEL_NAMES = {
      DEBUG => :DEBUG,
      INFO => :INFO,
      WARNING => :WARNING,
      ERROR => :ERROR
    }
    def self.log(level, msg)
      printf("[%s] - %s - %7s: %s\n",
        Time.now.strftime("%Y-%m-%d, %H:%M:%S"), 
        File.basename($0), 
        LEVEL_NAMES[level] || level, 
        msg) if @@level >= level
    end
  end
end
