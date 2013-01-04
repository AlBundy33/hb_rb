module Tools
  require 'logger'
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
    @@alread_redirected = false
    # redirects output to file (uses no tee-command!)
    #
    # +logfile+ the file to write to
    # +append+ append to existing file or create a new one
    # +stdout+ redirect stdout or not
    # +stderr+ redirect stderr or not
    # +block+ all output inside the block will be redirected to logfile
    def self.tee(logfile, append=true)
      raise "output is already redirected!" if @@alread_redirected
      @@alread_redirected = true
      file = File.open(logfile, append ? 'a' : 'w')
      stdout_old = $stdout.dup
      stderr_old = $stderr.dup
      stdout_r, stdout_w = IO.pipe
      stderr_r, stderr_w = IO.pipe
      t1 = Thread.new do
        while data = stdout_r.readpartial(1024) rescue nil
          stdout_old.write(data)
          file.write(data)
        end
        stdout_r.close
      end
      t2 = Thread.new do
        while data = stderr_r.readpartial(1024) rescue nil
          stderr_old.write(data)
          file.write(data)
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
        [stdout_w,stderr_w].each { |f| f.close }
        t1.join
        t2.join
        [stdout_old,stderr_old,file].each { |f| f.close }
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
      l.datetime_format = "%Y-%m-%d, %H:%M:%S,%L "
      return l
    end
  end
end
