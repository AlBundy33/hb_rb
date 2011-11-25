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
        return %x[ver].strip
      elsif command?("uname")
        return %x[uname -a].strip
      end
      return RUBY_PLATFORM
    end
  
    # returns the current platform
    def self.platform
      return @@platform if @@platform
      if RUBY_PLATFORM.casecmp("java") == 0
        current = uname()
      else
        current = RUBY_PLATFORM
      end
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
      f = whereis(cmd)
      return (not f.nil? and File.executable?(f))
    end
  
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
    def self.timeToSeconds(time)
      return -1 if time.nil? or time.strip.empty?
      times = time.split(/:/).reverse
      seconds = 0
      for i in (0...times.length)
        seconds += times[i].to_i * (60**i) 
      end
      return seconds
    end
    
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
end
