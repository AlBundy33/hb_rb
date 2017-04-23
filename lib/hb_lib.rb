# encoding: UTF-8
# for useful settings see: http://roku.yt1300.com/settings.html
require 'fileutils'
require 'optparse'

begin
  #https://trac.handbrake.fr/browser/trunk/scripts/manicure.rb
  require File.join(File.dirname(__FILE__), "manicure.rb")
  CAN_LOAD_PLIST = true
rescue LoadError
  CAN_LOAD_PLIST = false
end
require File.join(File.dirname(__FILE__), "tools.rb")
require File.join(File.dirname(__FILE__), "commands.rb")

module HandbrakeCLI
  class HBConvertInput
    attr_accessor :file, :fileSize
    def initialize(file)
      @file = file
      if File.file?(@file)
        @fileSize = Tools::FileTool::humanReadableSize(Tools::FileTool::size(@file) || 0)
      end
    end
    def to_s
      if @fileSize.nil?
        "#{file}"
      else
        "#{file} (#{@fileSize})"
      end
    end
  end
  class HBConvertResult
    attr_accessor :command, :file, :fileSize, :source, :title, :audiotitles, :subtitles, :output
  end
  class HBOptions
    attr_accessor :argv, :input, :output, :force,
                  :ipodCompatibility, :enableAutocrop, :languages, :audioTrackSettings, :audioEncoderSettings,
                  :maxHeight, :maxWidth, :subtitles, :preset, :mainFeatureOnly, :titles, :chapters,
                  :minLength, :maxLength, :skipDuplicates,
                  :onlyFirstTrackPerLanguage, :skipCommentaries,
                  :checkOnly, :xtra_args, :debug, :verbose,
                  :x264profile, :x264preset, :x264tune,
                  :testdata, :preview, :inputWaitLoops, :loops,
                  :logfile, :logOverride, :logOverview,
                  :inputDoneCommands, :outputDoneCommands,
                  :passedThroughArguments, :enableDecomb, :enableDetelecine, :looseAnamorphic,
                  :createEncodeLog, :encoder, :disableProgress, :burninForced, :skipForced, :quality

    def initialize()
      @quality = 20.0
      @skipForced = false
      @burninForced = false
      @inputWaitLoops = -1
      @loops = 1
      @force = false
      @ipodCompatibility = false
      @enableAutocrop = false
      @mainFeatureOnly = false
      @skipDuplicates = false
      @onlyFirstTrackPerLanguage = false
      @skipCommentaries = false
      @checkOnly = false
      @debug = false
      @verbose = false
      @inputDoneCommands = []
      @outputDoneCommands= []
      @passedThroughArguments = []
      @enableDecomb = true
      @enableDetelecine = true
      @looseAnamorphic = true
      @createEncodeLog = false
      @encoder = "x264"
      @disableProgress = false
    end

    def self.showUsageAndExit(options, msg = nil)
      puts options.to_s
      puts
      puts "hints:"
      puts "use raw disk devices (e.g. /dev/rdisk1) to ensure that libdvdnav can read the title"
      puts "see https://forum.handbrake.fr/viewtopic.php?f=10&t=26165&p=120036#p120035"
      puts
      puts "examples:"
      puts "convert main-feature with all original-tracks (audio and subtitle) for languages german and english"
      puts "#{File.basename($0)} --input /dev/rdisk1 --output \"~/Movie.m4v\" --movie"
      puts
      puts "convert all episodes with all original-tracks (audio and subtitle) for languages german and english"
      puts "#{File.basename($0)} --input /dev/rdisk1 --output \"~/Series_SeasonX_#pos#.m4v\" --episodes"
      puts
      puts "convert complete file or DVD with all tracks, languages etc."
      puts "#{File.basename($0)} --input /dev/rdisk1 --output \"~/Output_#pos#.m4v\""
      puts
      puts "convert MKV, add at first the english mixed down track and after that the copied english and german track"
      puts "#{File.basename($0)} --input ~/mymovie.mkv --output \"~/Output_#pos#.m4v\" --audio-track encoder=ca_aac,mixdown=dpl2,language=eng --audio-copy"
      puts
      puts "convert all local DVDs recursive in a directory"
      puts "#{File.basename($0)} --input \"~/DVD/**/VIDEO_TS\" --output \"~/#title#_#pos#.m4v\""
      puts
      puts "convert all MKVs in a directory"
      puts "#{File.basename($0)} --input \"~/MKV/*.mkv\" --output \"~/#title#.m4v\""
      puts
      puts "convert 10 DVDs, eject disc when done (OSX) and wait for next"
      puts "#{File.basename($0)} --input /dev/rdisk1 --output \"~/#title_#pos#.m4v\" --movie --preset \"Android Mid\" --loops 10 --input-done-cmd \"drutil tray eject\""
      puts
      if not msg.nil?
        puts msg
        puts
      end
      exit
    end
    
    def self.replace_argument(args, old, new)
      new_args = []
      args.each do |a|
        if a.eql?(old)
          new_args += [*new]
        else
          new_args << a
        end
      end
      return new_args
    end
    
    def self.replace_presets(argv)
      hbpresets = Handbrake::getHbPresets()
      return argv if hbpresets.empty?
      arguments = [*argv]
      loop_cnt = 100
      begin
        tmp = [*arguments]
        arguments = []
        preset_name = false
        tmp.each do |a|
          if a.eql? "--hbpreset"
            preset_name = true
          elsif preset_name
            raise "unknown preset #{a}" if not hbpresets.keys.include?(a)
            preset_name = false
            arguments += hbpresets[a]
          else
            arguments << a
          end
        end
        loop_cnt -= 1
        raise "configuration error detected" if loop_cnt <= 0
      end while arguments.include?("--hbpreset")
      return arguments
    end
    
    def self.registerHashType()
      OptionParser.accept :Hash do |arg,|
        key = ""
        value = ""
        result = {}
        add_to_key = true
        char_escaped = false
        string_escaped = false
        arg.split("").each do |c|
          if not char_escaped and c.eql?("'")
            string_escaped = !string_escaped
            next
          end
          if not char_escaped and c.eql?('\\')
            char_escaped = true
            next
          end
          if not (string_escaped or char_escaped) and c.eql?("=") and add_to_key
            add_to_key = false
            next
          end
          if not (string_escaped or char_escaped) and c.eql?(",")
            result[key.strip] = value.strip
            key = ""
            value = ""
            add_to_key = true
            next
          end
          if add_to_key
            key << c
          else
            value << c
          end
          char_escaped = false
        end
        result[key.strip] = value.strip unless key.strip.empty?
        result
      end
    end

    def self.parseArgs(argv)
      self.registerHashType()
      argv = self.replace_presets(argv)
      shorts = []
      shorts << ["--audio-copy", ["--audio-track", "encoder=copy"]]
      shorts << ["--audio-mixdown", ["--audio-track", "encoder=ca_aac,mixdown=dpl2"]]
      shorts << ["--movie", ["--default", "--main"]]
      shorts << ["--episodes", ["--default", "--min-length", "00:10:00", "--max-length", "00:50:00", "--skip-duplicates"]]
      shorts << ["--default", ["--audio", "deu,eng", "--subtitles", "deu,eng", "--audio-copy", "--skip-commentaries", "--only-first-track-per-language"]]
      shorts << ["--bluray", ["--no-decomb", "--no-detelecine", "--no-loose-anamorphic"]]
      0.upto(10) { shorts.each {|a| argv = self.replace_argument(argv, a.first, a.last) } }
      passed_through = []
      passed_through << ["--large-file", nil]
      passed_through << ["--encopts OPTIONS", "--encopts"]
      options = HBOptions.new
      optparse = OptionParser.new do |opts|
        opts.separator("")
        opts.separator("common")
        opts.on("--input INPUT", "input-source") { |arg| options.input = arg }
        output_help = ["output-file (mp4, m4v and mkv supported)"]
        output_help << "available place-holders"
        output_help << "#pos#               - title-number on input-source"
        output_help << "#size#              - resolution"
        output_help << "#fps#               - frames per second"
        output_help << "#ts#                - current timestamp"
        output_help << "#title#             - source-title (dvd-label, directory-basename, filename)"
        output_help << "#source#            - name of input"
        output_help << "#source_basename#   - name of input without extension"
        output_help << "#source_dirname#    - complete path to the input-file"
        output_help << "#source_parentname# - directoryname of the input-file"
        output_help << "#encoder#           - the used video-encoder"
        opts.on("--output OUTPUT", *output_help) { |arg| options.output = arg }
        opts.on("--force", "force override of existing files") { |arg| options.force = arg }
        opts.on("--check", "show only available titles and tracks") { |arg| options.checkOnly = arg }
        opts.on("--help", "Display this screen") { |arg| showUsageAndExit(opts) }
        presets = Handbrake::getHbPresets()
        unless presets.empty?
          opts.on("--hbpreset PRESET", "user defined presets (#{presets.keys.sort.join(', ')})")
        end 

        opts.separator("")
        opts.separator("output-options")
        opts.on("--compatibility", "enables iPod compatible output (only m4v and mp4)") { |arg| options.ipodCompatibility = arg }
        opts.on("--autocrop", "automatically crop black bars") { |arg| options.enableAutocrop = arg }
        opts.on("--quality QUALITY", "quality to use (current: #{options.quality})") do |arg|
          if "#{arg}".strip.empty? or arg.to_f < 0
            options.quality = nil
          else
            options.quality = arg
          end
        end
        opts.on("--max-width WIDTH", "maximum video width (e.g. 1920, 1280, 720)") { |arg| options.maxWidth = arg }
        opts.on("--max-height HEIGTH", "maximum video height (e.g. 1080, 720, 576)") { |arg| options.maxHeight = arg }
        opts.on("--audio LANGUAGES", Array, "the audio languages") { |arg| options.languages = arg }
        opts.on("--subtitles LANGUAGES", Array, "the subtitle languages") { |arg| options.subtitles = arg }
        opts.on("--lang LANGUAGES", Array, "sets audio and subtitle languges") do |arg|
          options.languages = arg
          options.subtitles = arg
        end
        opts.on("--burnin-forced", "Burn in the first forced subtitle") do |arg|
          options.burninForced = arg
        end
        audio_track_args = {
          "encoder" => "the audio encoder to use (allowed: #{(["copy", "auto"] + Handbrake::getAudioEncoders()).join(', ')}, default: copy)",
          "mixdown" => "allowed: #{(["auto"] + Handbrake::getAudioMixdowns()).join(', ')}), default: auto)", 
          "bitrate" => "the bitrate to use (default: 160kb/s)",
          "codec" => "the codec-filter to apply (regular expression)",
          "language" => "the language-filter to apply (space separated)"
        }
        opts.on("--audio-track SETTINGS", :Hash, *(["the audio-settings to use", "allowed options"] + audio_track_args.collect{|k,v| "#{k} - #{v}"})) { |arg|
          options.audioTrackSettings = [] if options.audioTrackSettings.nil?
          options.audioTrackSettings << arg
        }
        audio_encoder_args = {
          "track" => "regular expression for track (use * to set default settings)",
          "encoder" => "the audio encoder to use (allowed: #{(["copy"] + Handbrake::getAudioEncoders()).join(', ')})",
          "mixdown" => "allowed: #{(["auto"] + Handbrake::getAudioMixdowns()).join(', ')}))", 
          "bitrate" => "the bitrate to use"
        }
        opts.on("--audio-settings SETTINGS", :Hash, *(["encoding settings for auto-encoder depending on audio-type", "allowed options"] + audio_encoder_args.collect{|k,v| "#{k} - #{v}"})) { |arg|
          options.audioEncoderSettings = [] if options.audioEncoderSettings.nil?
          options.audioEncoderSettings << arg
        }
        opts.on("--preset PRESET", "the handbrake-preset to use", "allowed: #{Handbrake::getPresets().keys.sort.join(', ')})") { |arg| options.preset = arg }
        opts.on("--preview [RANGE]", "convert only a preview in RANGE (default: 00:01:00-00:02:00)") { |arg| options.preview = arg || "00:01:00-00:02:00" }
      
        opts.separator("")
        opts.separator("filter-options")
        opts.on("--main", "main-feature only") { |arg| options.mainFeatureOnly = arg }
        opts.on("--titles TITLES", Array, "the title-numbers to convert (use --check to see available titles)") { |arg| options.titles = arg }
        opts.on("--chapters CHAPTERS", "the chapters to convert (e.g. 2 or 3-4)") { |arg| options.chapters = arg }
        opts.on("--min-length DURATION", "the minimum-track-length - format hh:nn:ss") { |arg| options.minLength = arg }
        opts.on("--max-length DURATION", "the maximum-track-length - format hh:nn:ss") { |arg| options.maxLength = arg }
        opts.on("--skip-duplicates", "skip duplicate titles (checks block-size)") { |arg| options.skipDuplicates = arg }
        opts.on("--only-first-track-per-language", "convert only first audio-track per language") { |arg| options.onlyFirstTrackPerLanguage = arg }
        opts.on("--skip-commentaries", "ignore commentary-audio- and subtitle-tracks") { |arg| options.skipCommentaries = arg }
        opts.on("--skip-forced", "ignore forced subtitles") { |arg| options.skipForced = arg }
        
        opts.on("")
        opts.on("options passed through handbrake (see handbrake-help for info)")
        passed_through.each do |k,v|
          opts.on(k, "") { |arg|
            options.passedThroughArguments << (v || k)
            options.passedThroughArguments << arg if !arg.nil? and !v.nil?
          }
        end
        opts.on("--[no-]decomb") {|arg| options.enableDecomb = arg }
        opts.on("--[no-]detelecine") {|arg| options.enableDetelecine = arg }
        opts.on("--[no-]loose-anamorphic") { |arg| options.looseAnamorphic = arg }
          
        opts.separator("")
        opts.separator("logging")
        opts.on("--log [LOGFILE]", "write all output to LOGFILE") { |arg| options.logfile = arg || "hb.log" }
        opts.on("--log-override", "always override logfile") { |arg| options.logOverride = arg }
        opts.on("--log-overview LOGFILE", "write additional overview-file") { |arg| options.logOverview = arg }
        opts.on("--create-encode-log", "create the handbrake encode-log based on the outputfile-name") { |arg| options.createEncodeLog = arg}
      
        opts.separator("")
        opts.separator("expert-options")
        opts.on("--loops LOOPS", "processes input LOOPS times (default: 1)") { |arg| options.loops = arg.to_i }
        opts.on("--wait LOOPS", "retries LOOPS times to wait for input (default: unlimited)") { |arg| options.inputWaitLoops = arg.to_i }
        opts.on("--xtra ARGS", "additional arguments for handbrake") { |arg| options.xtra_args = arg }
        opts.on("--temp DIR", "use DIR as temp-directory") { |arg|
          t = File.absolute_path(arg)
          FileUtils.mkdir_p(t) unless File.directory?(t)
          ["TEMP", "TMP", "TMPDIR"].each {|n| ENV[n] = t }
        }
        opts.on("--debug", "enable debug-mode (doesn't start conversion)") { |arg| options.debug = arg }
        opts.on("--verbose", "enable verbose output") { |arg| options.verbose = arg }
        opts.on("--testdata FILE", "read info from/write info to file") { |arg| options.testdata = arg }
        opts.on("--encoder ENCODER", "sets the video-encoder to use (available: #{Handbrake::getEncoders().join(', ')})") {|arg|
          options.encoder = arg
        }
        opts.on("--qsv", "enables hardware-acceleration with qsv_h264 if available, otherwise x264 will be used") {
          encoders = Handbrake::getEncoders()
          if encoders.include?("qsv_h264")
            options.encoder = "qsv_h264"
          else
            puts "WARNING: QSV is not supported. available encoders are: #{encoders.join(', ')}"
            puts "to enable qsv please check https://forum.handbrake.fr/viewtopic.php?f=11&t=29498"
            puts
          end
        }
        opts.on("--x264-profile PRESET", "use x264-profile (#{Handbrake::X264_PROFILES.join(', ')})") { |arg| options.x264profile = arg }
        opts.on("--x264-preset PRESET", "use x264-preset (#{Handbrake::X264_PRESETS.join(', ')})") { |arg| options.x264preset = arg }
        opts.on("--x264-tune OPTION", "tune x264 (#{Handbrake::X264_TUNES.join(', ')})") { |arg| options.x264tune = arg }
        opts.on("--disable-progress", "disables handbrakes progress output") {|arg| options.disableProgress = true }

        commands = InputDoneCommands::create()
        unless commands.empty?
          opts.separator("")
          opts.separator("commands to run after input was processed")          
          commands.each do |c|
            param = "--input-#{c.id}"
            param << " #{c.arg_descr}" if c.needs_argument?
            opts.on(param, c.descr) {|arg|
              c.arg = arg
              options.inputDoneCommands << c
            }
          end
        end

        commands = OutputDoneCommands::create()
        unless commands.empty?
          opts.separator("")
          opts.separator("commands to run after output was created")          
          commands.each do |c|
            param = "--output-#{c.id}"
            param << " #{c.arg_descr}" if c.needs_argument?
            opts.on(param, c.descr) {|arg|
              c.arg = arg 
              options.outputDoneCommands << c
            }
          end
        end
      
        unless shorts.empty?
          opts.separator("")
          opts.separator("shorts")
          shorts.each do |s|
            opts.on(s.first, "sets: #{s.last.join(' ')}")
          end
        end
      end
      
      begin
        optparse.parse!(argv)
      rescue => e
        if not e.kind_of?(SystemExit)
          showUsageAndExit(optparse, e.to_s)
        else
          exit
        end
      end
      
      options.titles.collect!{ |t| t.to_i } if not options.titles.nil?
      
      if not Tools::OS::command2?(Handbrake::HANDBRAKE_CLI)
         showUsageAndExit(optparse,"HandbrakeCLI not found
download Handbrake CLI at http://handbrake.fr/downloads2.php for your platform
and copy the application-files to #{File::dirname(Handbrake::HANDBRAKE_CLI)}")
      end
      
      # check settings
      showUsageAndExit(optparse, "input not set") if options.input.nil?()
      showUsageAndExit(optparse, "output not set") if not options.checkOnly and options.output.nil?()
      showUsageAndExit(optparse, "unknown video-encoder #{options.encoder}") if not Handbrake::getEncoders().include?(options.encoder)
      options.audioTrackSettings = [{"encoder" => "auto"}] if options.audioTrackSettings.nil?
      options.audioTrackSettings.each do |arg|
        defaults = {
          "encoder" => "copy",
          "mixdown" => "auto",
          "bitrate" => "160",
          "codec" => nil,
          "language" => nil
        }
        defaults.each {|k,v| arg[k] = v if arg[k].nil? or arg[k].strip.empty? }
        arg["language"] = arg["language"].split(" ").collect{|l| l.strip } unless arg["language"].nil?
        allowed = {
          "encoder" => ["copy", "auto"] + Handbrake::getAudioEncoders(),
          "mixdown" => ["auto"] + Handbrake::getAudioMixdowns()
        }
        allowed.each do |k,v|
          showUsageAndExit(options, "wrong audio-track value #{arg[k]} for #{k} - allowed: #{v.join(', ')}") unless v.include?(arg[k])
        end
      end
      options.audioTrackSettings.uniq!
      options.audioEncoderSettings = [{"track" => "*", "encoder" => "copy"}] if options.audioEncoderSettings.nil?
      options.audioEncoderSettings.each do |arg|
        allowed = {
          "encoder" => ["copy"] + Handbrake::getAudioEncoders(),
          "mixdown" => ["auto"] + Handbrake::getAudioMixdowns()
        }
        showUsageAndExit(options, "no regex defined in audio-settings") if "#{arg['track']}".strip.empty?
        allowed.each do |k,v|
          showUsageAndExit(options, "wrong audio-setting value #{arg[k]} for #{k} - allowed: #{v.join(', ')}") if arg.has_key?(k) and !v.include?(arg[k])
        end  
      end
      showUsageAndExit(optparse,"unknown x264-profile: #{options.x264profile}") if not options.x264profile.nil? and not Handbrake::X264_PROFILES.include?(options.x264profile)
      showUsageAndExit(optparse,"unknown x264-preset: #{options.x264preset}") if not options.x264preset.nil? and not Handbrake::X264_PRESETS.include?(options.x264preset)
      showUsageAndExit(optparse,"unknown x264-tune option: #{options.x264tune}") if not options.x264tune.nil? and not Handbrake::X264_TUNES.include?(options.x264tune)
      showUsageAndExit(optparse,"unknown preset #{options.preset} (allowed: #{Handbrake::getPresets().keys.join(", ")})") if not options.preset.nil? and Handbrake::getPresets()[options.preset].nil?
      options.argv = argv
      return options
    end
  end

  class Handbrake
    include Tools

    def self.find_hb()
      # HandbrakeCLI in tool-folder
      tool_path = File.expand_path("#{File.dirname(__FILE__)}/../tools/handbrake/#{Tools::OS::platform().to_s.downcase}/HandBrakeCLI")
      return tool_path if Tools::OS::command2?(tool_path) 
      
      # HandbrakeCLI in PATH
      p = Tools::OS::whereis2("HandBrakeCLI")
      return p unless p.nil?
      
      # HandbrakeCLI not found
      return tool_path
    end

    HANDBRAKE_CLI = Handbrake::find_hb()
    
    AUDIO_MIXDOWN_DESCR = {
      "mono" => "Mono",
      "left_only" => "left channel",
      "right_only" => "right channel",
      "stereo" => "Stereo",
      "dpl1" => "Dolby Surround",
      "dpl2" => "Dolby Pro Logic II",
      "5point1" => "5.1",
      "6point1" => "6.1",
      "7point1" => "7.1",
      "5_2_lfe" => "7.1 (5F/2R/LFE)"
    }
    
    # http://handbrake.fr/doxy/documentation/libhb/html/common_8c.html
    AUDIO_ENCODER_DESCR = {
      "dts" => "DTS",
      "ffaac" => "AAC (ffmpeg)",
      "ffac3" => "AC3 (ffmpeg)",
      "lame" => "MP3 (lame)",
      "libvorbis" => "Vorbis (vorbis)",
      "ffflac" => "FLAC (ffmpeg)",
      "ffflac24" => "FLAC (24-bit)",
      "ca_aac" => "AAC (CoreAudio)",
      "ca_haac" => "HE-AAC (CoreAudio)",
      "faac" => "AAC (faac)",
      "av_aac" => "AAC (avcodec)",
      "fdk_aac" => "AAC (FDK)",
      "fdk_haac" => "HE-AAC (FDK)",
      "copy:aac" => "AAC Passthru",
      "ac3" => "AC3", 
      "copy:ac3" => "AC3 Passthru",
      "copy:dts" => "DTS Passthru",
      "copy:dtshd" => "DTS-HD Passthru",
      "mp3" => "MP3",
      "copy:mp3" => "MP3 Passthru",
      "vorbis" => "Vorbis",
      "flac16" => "FLAC 16-bit",
      "flac24" => "FLAC 24-bit",
      "copy" => "Auto Passthru"
    }
  
    X264_PROFILES = %w(baseline main high high10 high422 high444)
    X264_PRESETS = %w(ultrafast superfast veryfast faster fast medium slow slower veryslow placebo)
    X264_TUNES = %w(film animation grain stillimage psnr ssim fastdecode zerolatency)
    
    def self.getEncoders()
      cmd = "\"#{HANDBRAKE_CLI}\" --help 2>&1"
      output = %x[#{cmd}]
      result = []
      add = false
      output.each_line do |line|
        l = line.strip
        if l.start_with?("-e, --encoder")
          add = true
          next
        end
        next unless add
        break if l.start_with?("--")
        result << l
      end
      return result
    end
    
    def self.getAudioEncoders()
      cmd = "\"#{HANDBRAKE_CLI}\" --help 2>&1"
      output = %x[#{cmd}]
      result = []
      add = false
      output.each_line do |line|
        l = line.strip
        if l.start_with?("-E, --aencoder")
          add = true
          next
        end
        next unless add
        break if l.start_with?("\"copy:<type>\" will pass")
        next if l.start_with?("copy")
        result << l
      end
      return result
    end
    
    def self.getAudioMixdowns()
      cmd = "\"#{HANDBRAKE_CLI}\" --help 2>&1"
      output = %x[#{cmd}]
      result = []
      add = false
      output.each_line do |line|
        l = line.strip
        if l.start_with?("-6, --mixdown")
          add = true
          next
        end
        next unless add
        break if l.include?(" ")
        result << l
      end
      return result
    end

    def self.getPresets()
      result = {}
      mergeHash(result, loadBuiltInPresets())
      Dir.glob(File.join(File.dirname($0), "*.plist")) do |f|
        mergeHash(result, loadPlist(File.expand_path(f)))
      end
      return result
    end
    
    def self.getHbPresets()
      result = {}
      fname = File.join(File.dirname($0), "hb.presets")
      if File.exist?(fname)
        pname = nil
        File.open(fname).each do |line|
          l = line.strip.chomp.chomp
          next if l.empty? or l.start_with?(";")
          if l.start_with?("[") and l.end_with?("]")
            pname = l[1..-2]
            result[pname] = [] unless pname.nil? or pname.strip.empty?
            next
          end
          result[pname] << l unless pname.nil? or pname.strip.empty?
        end
      end
      return result
    end
    
    def self.mergeHash(h, n)
      return if n.nil?
      n.each do |k,v|
        #puts "overriding #{k} with #{v}" if h.include?(k)
        h[k] = v
      end
    end
    
    if CAN_LOAD_PLIST
      class DisplayToString < Display
        def initialize(h,o)
          @lines = []
          super(h,o)
        end
  
        def puts(msg)
          @lines << msg
        end
        
        def output
          @lines.join("\n")
        end
      end
    end
    
    def self.loadPlist(path)
      p = File.expand_path(path)
      result = {}
      return result unless CAN_LOAD_PLIST
      if File.exists?(p)
        options = OpenStruct.new
        options.cliraw = false
        options.cliparse = true
        options.api = false
        options.apilist = false
        options.header = false
        plist = Plist::parse_xml( p )
        plist.each do |e|
          e["ChildrenArray"] = [] if e["ChildrenArray"].nil?
          e["Folder"] = nil if e["Folder"].nil? or e["Folder"] == 0
          def e.[](key)
            v = super(key)
            #puts "#{key} #{v}"
            return v unless v.nil?
            return nil if keys.include?(key)
            return ""
          end
        end
        output = DisplayToString.new(plist, options).output
        #puts output
        mergeHash(result, parsePresets(output))
      end
      return result
    end
    
    def self.loadBuiltInPresets()
      cmd = "\"#{HANDBRAKE_CLI}\" --preset-list 2>&1"
      output = %x[#{cmd}]
      return parsePresets(output)
    end
    
    def self.parsePresets(output)
      preset_pattern = /\+ (.*?): (.*)/
      result = {}
      output.each_line do |line|
        next if not line =~ preset_pattern
        info = line.scan(preset_pattern)[0]
        result[info[0].strip] = info[1].strip
      end
      return result
    end
    
    def self.fix_str(str)
      begin
        return Tools::StringTool::encode(str, 'utf-8', 'utf-8')
      rescue => e
        HandbrakeCLI::logger.info("error reading line: #{str} (#{e})")
        begin
          return Tools::StringTool::encode(str, 'utf-8', 'utf-8', true)
        rescue => e2
          # ignore
        end
      end
      str
    end
  
    def self.readInfo(input, debug = false, testdata = nil, titles = nil)
      path = File.expand_path(input)

      cmd = "\"#{HANDBRAKE_CLI}\" -i \"#{path}\" --scan --title #{titles.nil? || titles.size != 1 ? 0 : titles.first} 2>&1"
      if !testdata.nil? and File.exists?(testdata)
        puts "reading file #{testdata}" if debug
        output = File.read(testdata)
      else
        puts cmd if debug
        output = %x[#{cmd}]
      end
      if !testdata.nil? and !File.exists?(testdata)
        File.open(testdata, 'w') { |f| f.write(output) }
      end
  
      dvd_title_pattern = /libdvdnav: DVD Title: (.*)/
      dvd_alt_title_pattern = /libdvdnav: DVD Title \(Alternative\): (.*)/
      dvd_serial_pattern = /libdvdnav: DVD Serial Number: (.*)/
      main_feature_pattern = /\+ Main Feature/
  
      title_blocks_pattern = /\+ vts .*, ttn .*, cells .* \(([0-9]+) blocks\)/
      title_pattern = /\+ title ([0-9]+):/
      title_info_pattern = /\+ size: ([0-9]+x[0-9]+).*, ([0-9.]+) fps/
      in_audio_section_pattern = /\+ audio tracks:/
      audio_pattern = /\+ ([0-9]+), (.*?) \(iso639-2: (.*?)\), ([0-9]+Hz), ([0-9]+bps)/
      file_audio_pattern = /\+ ([0-9]+), (.*?) \(iso639-2: (.*?)\)/
      in_subtitle_section_pattern = /\+ (subtitles|subtitle tracks):/
      subtitle_pattern = /\+ ([0-9]+), (.*?) \(iso639-2: (.*?)\)/
      duration_pattern = /\+ duration: (.*)/
      chapter_pattern = /\+ ([0-9]+): cells (.*), ([0-9]+) blocks, duration (.*)/
  
      source = MovieSource.new(path)
      title = nil
  
      in_audio_section = false
      in_subtitle_section = false
      has_main_feature = false
      output.each_line do |line|
        line.chomp!
        puts "out> #{line}" if debug
        
        begin
          line.match(/.*/)
        rescue => e
          puts "> skipping line: #{line} (#{e})" if debug
          next
        end
  
        if line.match(dvd_title_pattern)
          puts "> match: dvd-title" if debug
          info = line.scan(dvd_title_pattern)[0]
          source.title = info[0].strip
        elsif line.match(dvd_alt_title_pattern)
          puts "> match: dvd-alt-title" if debug
          info = line.scan(dvd_alt_title_pattern)[0]
          source.title_alt = info[0].strip
        elsif line.match(dvd_serial_pattern)
          puts "> match: dvd-serial" if debug
          info = line.scan(dvd_serial_pattern)[0]
          source.serial = info[0].strip
        elsif line.match(in_audio_section_pattern)
          in_audio_section = true
          in_subtitle_section = false
        elsif line.match(in_subtitle_section_pattern)
          in_audio_section = false
          in_subtitle_section = true
        elsif line.match(title_pattern)
          puts "> match: title" if debug
          info = line.scan(title_pattern)[0]
          title = Title.new(info[0])
          source.titles().push(title)
        end
  
        next if title.nil?
  
        if line.match(main_feature_pattern)
          puts "> match: main-feature" if debug
          title.mainFeature = true
          has_main_feature = true
        elsif line.match(title_blocks_pattern)
          puts "> match: blocks" if debug
          info = line.scan(title_blocks_pattern)[0]
          title.blocks = info[0].to_i
        elsif line.match(title_info_pattern)
          puts "> match: info" if debug
          info = line.scan(title_info_pattern)[0]
          title.size = info[0]
          title.fps = info[1]
        elsif line.match(duration_pattern)
          puts "> match: duration" if debug
          info = line.scan(duration_pattern)[0]
          title.duration = info[0]
        elsif line.match(chapter_pattern)
          puts "> match: chapter" if debug
          info = line.scan(chapter_pattern)[0]
          chapter = Chapter.new(info[0])
          chapter.cells = info[1]
          chapter.blocks = info[2]
          chapter.duration = info[3]
          title.chapters().push(chapter)
        elsif in_audio_section and line.match(audio_pattern)
          puts "> match: audio" if debug
          info = line.scan(audio_pattern)[0]
          track = AudioTrack.new(info[0], info[1])
          if info[1].match(/\((.*?)\)\s*\((.*?)\)\s*\((.*?)\)\s*/)
            info2 = info[1].scan(/\((.*?)\)\s*\((.*?)\)\s*\((.*?)\)\s*/)[0]
            track.codec = info2[0]
            track.comment = info2[1]
            track.channels = info2[2]
          elsif info[1].match(/\((.*?)\)\s*\((.*?)\)\s*/)
            info2 = info[1].scan(/\((.*?)\)\s*\((.*?)\)\s*/)[0]
            track.codec = info2[0]
            track.channels = info2[1]
          end
          track.lang = info[2]
          track.rate = info[3]
          track.bitrate = info[4]
          title.audioTracks().push(track)
        elsif in_audio_section and line.match(file_audio_pattern)
          puts "> match: audio" if debug
          info = line.scan(file_audio_pattern)[0]
          track = AudioTrack.new(info[0], info[1])
          if info[1].match(/\((.*?)\)\s*\((.*?)\)\s*\((.*?)\)\s*/)
            info2 = info[1].scan(/\((.*?)\)\s*\((.*?)\)\s*\((.*?)\)\s*/)[0]
            track.codec = info2[0]
            track.comment = info2[1]
            track.channels = info2[2]
          elsif info[1].match(/\((.*?)\)\s*\((.*?)\)\s*/)
            info2 = info[1].scan(/\((.*?)\)\s*\((.*?)\)\s*/)[0]
            track.codec = info2[0]
            track.channels = info2[1]
          end
          track.lang = info[2]
          title.audioTracks().push(track)
        elsif in_subtitle_section and line.match(subtitle_pattern)
          puts "> match: subtitle" if debug
          info = line.scan(subtitle_pattern)[0]
          subtitle = Subtitle.new(info[0], info[1], info[2])
          if info[1].match(/\((.*?)\)/)
            info2 = info[1].scan(/\((.*?)\)/)[0]
            subtitle.comment = info2[0]
          end
          title.subtitles().push(subtitle)
        end
      end
      if not has_main_feature
        longest = nil
        source.titles.each do |t|
          if longest.nil? 
            longest = t
            next
          end
          longest_duration = TimeTool::timeToSeconds(longest.duration)
          title_duration = TimeTool::timeToSeconds(t.duration)
          longest = t if title_duration > longest_duration
        end
        longest.mainFeature = true if not longest.nil?
      end
      
      return source
    end

    def self.convert(options, titleMatcher, audioMatcher, subtitleMatcher)
      source = Handbrake::readInfo(options.input, options.debug && options.verbose, options.testdata, options.titles)
      created = []
      if options.checkOnly
        puts source.info
        return created
      end
      
      if source.titles.empty?
        HandbrakeCLI::logger.debug("#{source.path} contains no titles")
        return created
      end
  
      converted = []
      if options.minLength.nil?
        minLength = -1
      else
        minLength = TimeTool::timeToSeconds(options.minLength)
      end
      if options.maxLength.nil?
        maxLength = -1
      else
        maxLength = TimeTool::timeToSeconds(options.maxLength)
      end
  
      HandbrakeCLI::logger.info "processing #{source}"
      source.titles().each do |title|
        HandbrakeCLI::logger.debug("checking #{title}")
        
        if options.mainFeatureOnly and not title.mainFeature
          HandbrakeCLI::logger.debug("skipping title because it's not the main-feature")
          next
        elsif not titleMatcher.matches(title)
          HandbrakeCLI::logger.debug("skipping unwanted title")
          next
        end
        tracks = audioMatcher.filter(title.audioTracks)
        subtitles = subtitleMatcher.filter(title.subtitles)
        
        duration = TimeTool::timeToSeconds(title.duration)
        if minLength >= 0 and duration < minLength
          HandbrakeCLI::logger.debug("skipping title because it's duration is too short (#{TimeTool::secondsToTime(minLength)} <= #{TimeTool::secondsToTime(duration)} <= #{TimeTool::secondsToTime(maxLength)})")
          next
        end
        if maxLength >= 0 and duration > maxLength
          HandbrakeCLI::logger.debug("skipping title because it's duration is too long (#{TimeTool::secondsToTime(minLength)} <= #{TimeTool::secondsToTime(duration)} <= #{TimeTool::secondsToTime(maxLength)})")
          next
        end
        if tracks.empty?()
          HandbrakeCLI::logger.debug("skipping title because it contains no audio-tracks (available: #{title.audioTracks})")
          next
        end
        if options.skipDuplicates and not title.blocks().nil? and title.blocks() >= 0 and converted.include?(title.blocks())
          HandbrakeCLI::logger.debug("skipping because source contains it twice")
          next
        end
        
        converted.push(title.blocks()) if not title.blocks().nil?

        result = HBConvertResult.new
        result.source = source
        result.title = title
        result.audiotitles = tracks
        result.subtitles = subtitles
  
        outputFile = File.expand_path(options.output)
        source_title = source.name.dup
        source_title.gsub!(/[_]+/, " ")
        source_title = Tools::FileTool::fixname(source_title)
        source_title.gsub!(/[\s]+/, " ")
        source_basename = source.input_name(true) || source_title
        source_dirname = File.expand_path(File.dirname(source.path))
        source_parentname = File.basename(source_dirname)
        outputFile.gsub!("#pos#", "%02d" % title.pos)
        outputFile.gsub!("#size#", title.size || "")
        outputFile.gsub!("#fps#", title.fps || "")
        outputFile.gsub!("#ts#", Time.new.strftime("%Y-%m-%d_%H_%M_%S"))
        outputFile.gsub!("#title#", source_title)
        outputFile.gsub!("#source#", source.input_name(false) || source_title)
        outputFile.gsub!("#source_basename#", source_basename)
        outputFile.gsub!("#source_dirname#", source_dirname)
        outputFile.gsub!("#source_parentname#", source_parentname)
        outputFile.gsub!("#encoder#", options.encoder || "")
        if not options.force
          if File.exists?(outputFile) or Dir.glob("#{File.dirname(outputFile)}/*.#{File.basename(outputFile)}").size() > 0
            HandbrakeCLI::logger.info("skipping title because \"#{outputFile}\" already exists")
            next
          end
        end
  
        HandbrakeCLI::logger.debug("converting #{title}")
  
        ext = File.extname(outputFile).downcase
        ismp4 = false
        ismkv = false
        if ext.eql?(".mp4") or ext.eql?(".m4v")
          ismp4 = true
        elsif ext.eql?(".mkv")
          ismkv = true
        else
          raise "error unsupported extension #{ext}"
        end
  
        command = "\"#{HANDBRAKE_CLI}\""
        command << " --input \"#{source.path()}\""
        command << " --output \"#{outputFile}\""
        command << " --chapters #{options.chapters}" if not options.chapters.nil?
        command << " --verbose" if options.verbose
  
        preset_arguments = nil
        if not options.preset.nil?
          preset_arguments = getPresets()[options.preset]
          if not preset_arguments.nil?
            cleaned_preset_arguments = preset_arguments.dup
            [
              "-E", "--aencoder",
              "-a", "--audio",
              "-R", "--arate",
              "-f", "--format",
              "-6", "--mixdown",
              "-B", "--ab",
              "-D", "--drc"
              ].each do |a|
              cleaned_preset_arguments.gsub!(/#{a} [^ ]+[ ]*/, "")
            end
            #puts cleaned_preset_arguments
            #puts preset_arguments
            # set preset arguments now and override some of them later
            command << " #{cleaned_preset_arguments}"
          end
        end
  
        if options.preset.nil?
          command << " --encoder #{options.encoder}"
          command << " --quality #{options.quality}" if !options.quality.nil?
          command << " --decomb" if options.enableDecomb
          command << " --detelecine" if options.enableDetelecine
          command << " --crop 0:0:0:0" if not options.enableAutocrop
          if options.looseAnamorphic and !options.ipodCompatibility
            command << " --loose-anamorphic"
          end
          if ismp4 and options.ipodCompatibility
            command << " --ipod-atom"
            command << " --encopts level=30:bframes=0:cabac=0:weightp=0:8x8dct=0" if preset.nil?
          end
        end
        
        command << " --maxHeight #{options.maxHeight}" if options.maxHeight
        command << " --maxWidth #{options.maxWidth}" if options.maxWidth
        command << " --x264-profile #{options.x264profile}" if not options.x264profile.nil?
        command << " --x264-preset #{options.x264preset}" if not options.x264preset.nil?
        command << " --x264-tune #{options.x264tune}" if not options.x264tune.nil?
  
        if ismp4
          command << " --format mp4"
          command << " --optimize"
        elsif ismkv
          command << " --format mkv"
        end
  
        command << " --markers"
        
        if not options.preview.nil?
          p = options.preview.split("-",2)
          if p.size == 1
            start_at = "00:01:00"
            stop_at = Tools::TimeTool::secondsToTime(Tools::TimeTool::timeToSeconds(start_at) + Tools::TimeTool::timeToSeconds(p.first))
          else
            start_at = p.first
            stop_at = Tools::TimeTool::secondsToTime(Tools::TimeTool::timeToSeconds(p.last) - Tools::TimeTool::timeToSeconds(start_at))
          end
          command << " --start-at duration:#{Tools::TimeTool::timeToSeconds(start_at)}"
          command << " --stop-at duration:#{Tools::TimeTool::timeToSeconds(stop_at)}"
        end
        
        command << " --title #{title.pos}"
        
        use_preset_settings = !options.preset.nil?
  
        # audio
        audio_settings_list = []
        first_audio_track = nil
        tracks.each do |t|
  
          HandbrakeCLI::logger.debug("checking audio-track #{t}")
          if use_preset_settings
            audio_settings = {}
            value = preset_arguments.match(/(?:-a|--audio) ([^ ]+)/)[1]
            track_count = value.split(",").size
            audio_settings["audio"] = ([t.pos] * track_count).join(",") 
            value = preset_arguments.match(/(?:-E|--aencoder) ([^ ]+)/)[1]
            audio_settings["encoder"] = value unless value.nil? 
            value = preset_arguments.match(/(?:-R|--arate) ([^ ]+)/)[1]
            audio_settings["rate"] = value unless value.nil?
            value = preset_arguments.match(/(?:-6|--mixdown) ([^ ]+)/)[1]
            audio_settings["mixdown"] = value unless value.nil?
            value = preset_arguments.match(/(?:-B|--ab) ([^ ]+)/)[1]
            audio_settings["ab"] = value unless value.nil?
            value = preset_arguments.match(/(?:-D|--drc) ([^ ]+)/)[1]
            audio_settings["drc"] = value unless value.nil?
            audio_settings["name"] = (["#{t.descr(true, true)}"] * track_count).join(",")
            ["audio", "encoder", "rate", "mixdown", "ab", "drc", "name"].each do |k|
              audio_settings[k] = audio_settings[k].split(",")
              raise "invalid audio settings" if audio_settings[k].size != audio_settings["audio"].size
            end
            audio_settings["audio"].size.times do |i|
              as = {}
              audio_settings.keys.each do |k|
                as[k] = audio_settings[k][i]
              end
              if as["mixdown"].eql?("auto")
                as["name"] = "#{t.descr(true, false)}"
              else
                as["name"] = "#{t.descr(true, true)} (#{AUDIO_MIXDOWN_DESCR[as["mixdown"]] || as["mixdown"]})"
              end
              audio_settings_list << as
            end
            HandbrakeCLI::logger.debug("adding audio-track: #{t}")
            first_audio_track = t if first_audio_track.nil?
          else
            options.audioTrackSettings.each do |at|
              atc = at.dup
              if atc["encoder"].eql?("auto") and !options.audioEncoderSettings.nil?
                use_default = true
                options.audioEncoderSettings.each do |s|
                  if !s["track"].eql?("*") and !s["track"].eql?(".*") and t.to_s.match(s["track"]) 
                    s.each do |k,v|
                      next if k.nil? or k.strip.empty? or v.nil? or v.strip.empty? or k.eql?("track")
                      atc[k] = v
                    end
					use_default = false
                  end
                end
                if use_default
                  options.audioEncoderSettings.each do |s|
                    if s["track"].eql?("*") or s["track"].eql?(".*")
                      s.each do |k,v|
                        next if k.nil? or k.strip.empty? or v.nil? or v.strip.empty? or k.eql?("track")
                        atc[k] = v
                      end
                    end
                  end
                end
              end
              # no default found - so skip this track
              next if atc["encoder"].eql?("auto")

              audio_settings = {}
              #puts atc["encoder"] + ": " + t.descr.to_s + " =~ " + /#{atc["codec"]}/.to_s + " -> " + (!!("#{t.descr}" =~ /#{atc["codec"]}/)).to_s  
              next if !atc["language"].nil? and !atc["language"].include?(t.lang)
              next if !atc["codec"].nil? and !("#{t.descr}" =~ /#{atc["codec"]}/)
              #puts atc["encoder"] + ": " + t.descr
              audio_settings["audio"] = t.pos
              audio_settings["encoder"] = atc["encoder"]
              audio_settings["rate"] = "auto"
              if atc["encoder"].eql?("copy")
                audio_settings["mixdown"] = "auto"
                audio_settings["ab"] = "auto"
                audio_settings["name"] = "#{t.descr}"
              else
                audio_settings["mixdown"] = atc["mixdown"]
                audio_settings["ab"] = atc["bitrate"]
                if atc["mixdown"].eql?("auto")
                  audio_settings["name"] = "#{t.descr(true, false)}"
                else
                  audio_settings["name"] = "#{t.descr(true, true)} (#{AUDIO_MIXDOWN_DESCR[atc["mixdown"]] || atc["mixdown"]})"
                end
              end
              audio_settings["drc"] = "0.0"
              audio_settings_list << audio_settings
              HandbrakeCLI::logger.debug("adding audio-track: #{t}")
              first_audio_track = t if first_audio_track.nil?
			  break
            end            
          end
        end
        
        paudio = []
        paencoder = []
        parate = []
        pmixdown = []
        pab = []
        pdrc = []
        paname = []
        audio_settings_list.each do |s|
          paudio << s["audio"]
          paencoder << s["encoder"]
          pmixdown << s["mixdown"]
          pab << s["ab"]
          pdrc << s["drc"]
          paname << s["name"]
        end

        if paudio.empty?()
           HandbrakeCLI::logger.debug("skipping title because found no audio-tracks to add")
           next
         end

        command << " --audio #{paudio.join(',')}"
        command << " --aencoder #{paencoder.join(',')}" unless paencoder.empty?
        command << " --arate #{parate.join(',')}" unless parate.empty?
        command << " --mixdown #{pmixdown.join(',')}" unless pmixdown.empty?
        command << " --ab #{pab.join(',')}" unless pab.empty?
        command << " --drc #{pdrc.join(',')}" unless pdrc.empty?
        command << " --aname \"#{paname.join('","')}\""
        unless use_preset_settings
          if ismp4
            command << " --audio-fallback faac"
          else
            command << " --audio-fallback lame"
          end
        end

        # preserve fps to keep encoded audio in sync
        allowed_fps = ["5", "10", "12", "15", "23.976", "24", "25", "29.97", "30", "50", "59.94", "60"]
        if !title.fps.nil? and !title.fps.strip.empty? and allowed_fps.include?(title.fps)
          command << " --cfr" 
          command << " --rate #{title.fps}"
        end
  
        # subtitles
        psubtitles = subtitles.collect{ |s| s.pos }
        # find the subtitle to burn in
        forced_subtitle = nil
        if options.burninForced and !first_audio_track.nil?
          title.subtitles.each do |s|
            next unless s.forced?
            next unless s.lang().eql?(first_audio_track.lang())
            forced_subtitle = s
            break
          end
        end
        # add the subtitle to burn in if not in list
        psubtitles << forced_subtitle.pos if !forced_subtitle.nil? and !psubtitles.include?(forced_subtitle.pos)
        # add subtitles
        command << " --subtitle #{psubtitles.join(',')}" if not psubtitles.empty?()
        # find index of subtitle to burn in
        forced_subtitle_idx = 0
        unless forced_subtitle.nil?
          psubtitles.each do |s|
            forced_subtitle_idx += 1
            break if s == forced_subtitle.pos
          end
        end
        # burn in the subtitle
        command << " --subtitle-burn #{forced_subtitle_idx}" if forced_subtitle_idx > 0
          
        # arguments to delegate...
        command << " #{options.xtra_args}" if not options.xtra_args.nil?

        # passthroug arguments
        command << " " + options.passedThroughArguments.join(" ")
        if options.createEncodeLog
          command << " 2>\"#{outputFile}_encode.log\""
        elsif not options.verbose
          command << " 2>#{Tools::OS::nullDevice()}"
        end
        if options.disableProgress
          command << " 1>#{Tools::OS::nullDevice()}"
        end

        start_time = Time.now
        HandbrakeCLI::logger.info "input: #{source}"
        HandbrakeCLI::logger.info "  title #{title.pos}#{title.mainFeature ? " (main-feature)" : ""} #{title.duration} #{title.size} (blocks: #{title.blocks()})" 
        unless title.audioTracks.empty?
          HandbrakeCLI::logger.info "  audio-tracks"
          title.audioTracks.each do |t|
            if options.verbose or options.debug
              HandbrakeCLI::logger.info "    - #{t}"
            else
              HandbrakeCLI::logger.info "    - track #{t.pos}: [#{t.lang}] #{t.descr}"
            end
          end
        end
        unless title.subtitles.empty?
          HandbrakeCLI::logger.info "  subtitles"
          title.subtitles.each do |s|
            HandbrakeCLI::logger.info "    - track #{s.pos}: [#{s.lang}] #{s.descr}"
          end
        end
        HandbrakeCLI::logger.info "output: #{outputFile}"
        if not tracks.empty?
          HandbrakeCLI::logger.info "  audio-tracks"
          paudio.each_with_index do |t,i|
            HandbrakeCLI::logger.info "    - track #{t}: #{paname[i] rescue nil || t.descr} - #{(AUDIO_ENCODER_DESCR[paencoder[i]] rescue nil) || paencoder[i]}"
          end
        end
        if not subtitles.empty?
          HandbrakeCLI::logger.info "  subtitles"
          subtitles.each do |s|
            HandbrakeCLI::logger.info "    - track #{s.pos}: #{s.descr}"
          end
        end
  
        HandbrakeCLI::logger.info(command)
        if not options.testdata.nil?
          result.file = outputFile
          result.command = command
          created << result
        elsif not options.debug
          parentDir = File.dirname(outputFile)
          FileUtils.mkdir_p(parentDir) unless File.directory?(parentDir)
          begin
            Tools::Loggers::tee(command,HandbrakeCLI::logger)
            return_code = $?
          rescue Interrupt => e
            puts
            return_code = 130
          end
          
          if File.exists?(outputFile)
            size = Tools::FileTool::size(outputFile)
            if return_code != 0
              HandbrakeCLI::logger.info("Handbrake exited with return-code #{return_code} - removing file #{File.basename(outputFile)}")
              File.delete(outputFile)
              converted.delete(title.blocks())
            elsif size >= 0 and size < (1 * 1024 * 1024)
              HandbrakeCLI::logger.info("file-size only #{Tools::FileTool::humanReadableSize(size)} - removing file #{File.basename(outputFile)}")
              File.delete(outputFile)
              converted.delete(title.blocks())
            else
              HandbrakeCLI::logger.info("created file #{outputFile} (#{Tools::FileTool::humanReadableSize(size)})")
              if size >= 4 * 1024 * 1024 * 1024 and !command =~ /--large-file/
                HandbrakeCLI::logger.info("file maybe useless because it's over 4GB and --large-file was not specified")
              end
              result.file = outputFile
              result.fileSize = Tools::FileTool::humanReadableSize(Tools::FileTool::size(outputFile) || 0)
              result.command = command
              result.output = readInfo(outputFile, false, nil)
              options.outputDoneCommands.each do |command|
                cmd = command.create_command(outputFile)
                if cmd.nil?
                  HandbrakeCLI::logger.debug("[#{command}] #{outputFile} (#{command.arg})")
                  command.run(outputFile)
                else
                  HandbrakeCLI::logger.debug("[#{command}] #{cmd}")
                  Tools::Loggers::tee(cmd, HandbrakeCLI::logger)
                end
                raise "command #{cmd} failed (return-code: #{$?}" if $? != 0
              end
              created << result
            end
          else
            HandbrakeCLI::logger.info("file #{outputFile} not created")
          end
        end
        end_time = Time.now
        required_time = Tools::TimeTool::secondsToTime((end_time - start_time).round)
        HandbrakeCLI::logger.info("== done (required time: #{required_time}) =================================")
        raise Interrupt if return_code == 130
      end
      unless created.empty?
        options.inputDoneCommands.each do |command|
          cmd = command.create_command(options.input)
          if cmd.nil?
            HandbrakeCLI::logger.debug("[#{command}] #{options.input} (#{command.arg})")
            command.run(options.input)
          else
            HandbrakeCLI::logger.debug("[#{command}] #{cmd}")
            Tools::Loggers::tee(cmd, HandbrakeCLI::logger)
          end
          raise "command #{cmd} failed (return-code: #{$?}" if $? != 0
        end
      end
      return created
    end
  end
  
  class Chapter
    attr_accessor :pos, :cells, :blocks, :duration
    def initialize(pos)
      @pos = pos.to_i
      @duration = nil
      @cells = nil
      @blocks = nil
    end
  
    def to_s
      "#{pos}. #{duration} (cells=#{cells}, blocks=#{blocks})"
    end
  end
  
  class Subtitle
    attr_accessor :pos, :descr, :comment, :lang
    def initialize(pos, descr, lang)
      @pos = pos.to_i
      @lang = lang
      @descr = descr
      @comment = nil
    end
  
    def commentary?()
      return @descr.downcase().include?("commentary")
    end
    
    def forced?()
      return @descr.downcase().include?("forced")
    end
  
    def to_s
      "#{pos}. #{descr} (lang=#{lang}, comment=#{comment}, commentary=#{commentary?()}, forced=#{forced?()})"
    end
  end
  
  class AudioTrack
    attr_accessor :pos, :descr, :codec, :comment, :channels, :lang, :rate, :bitrate
    def initialize(pos, descr)
      @pos = pos.to_i
      @descr = descr
      @codec = nil
      @comment = nil
      @channels = nil
      @lang = nil
      @rate = nil
      @bitrate = nil
    end
    
    def descr(remove_codec = false, remove_channels = false)
      d = @descr.dup
      d.gsub!(/\s*[(]?#{codec}[)]?/, "") if remove_codec
      d.gsub!(/\s*[(]?#{channels}[)]?/, "") if remove_channels
      d.strip!
      return d
    end
  
    def commentary?()
      return @descr.downcase().include?("commentary")
    end
    
    def forced?()
      return false
    end
  
    def to_s
      "#{pos}. #{descr} (codec=#{codec}, channels=#{channels}, lang=#{lang}, comment=#{comment}, rate=#{rate}, bitrate=#{bitrate}, commentary=#{commentary?()})"
    end
  end
  
  class Title
    attr_accessor :pos, :audioTracks, :subtitles, :chapters, :size, :fps, :duration, :mainFeature, :blocks
    def initialize(pos)
      @pos = pos.to_i
      @blocks = -1
      @audioTracks = []
      @subtitles = []
      @chapters = []
      @size = nil
      @fps = nil
      @duration = nil
      @mainFeature = false
    end
  
    def to_s
      "title #{"%02d" % pos}: #{duration}, #{size}, #{fps} fps, main-feature: #{mainFeature()}, blocks: #{blocks}, chapters: #{chapters.length}, audio-tracks: #{audioTracks.collect{|t| t.lang}.join(",")}, subtitles: #{subtitles.collect{|s| s.lang}.join(",")}"
    end
  end
  
  class MovieSource
    attr_accessor :title, :title_alt, :serial, :titles, :path
    def initialize(path)
      @titles = []
      @path = path
      @title = nil
      @title_alt = nil
      @serial = nil
    end
    
    def name(use_alt = false)
      return @title_alt if usable?(@title_alt) and use_alt
      return @title if usable?(@title)
      name = input_name(true)
      return name if usable?(name)
      return "unknown"
    end
    
    def input_name(without_extension = false)
      if File.directory?(path)
        if path.length < 4 and path[1] == ?:
          if Tools::OS::platform?(Tools::OS::WINDOWS)
            output = %x[vol #{path[0..1]}]
            idx = -1
            tokens = []
            output.lines.first().split.each do |t|
              idx += 1 if t.upcase.eql?(path[0].chr.upcase) or t.upcase.eql?(path[0..1].upcase) or idx >= 0
              tokens << t if idx > 1
            end
            name = tokens.join(" ")
          else
            name = path[0].chr
          end
        else
          name = File.basename(path())
          name = File.basename(File.dirname(path)) if ["VIDEO_TS", "AUDIO_TS"].include?(name)
        end
      else
        if without_extension
          name = File.basename(path(), ".*")
        else
          name = File.basename(path())
        end
      end
      return nil if name.strip.empty?
      return name.strip
    end

    def usable?(str)
      return false if str.nil?
      return false if str.strip.empty?
      return false if str.strip.eql? "unknown"
      return true
    end
  
    def info
      s = "#{self}"
      titles().each do |t|
        s << "\n#{t}"
        s << "\n  audio-tracks:"
        t.audioTracks().each do |e|
          s << "\n    #{e}"
        end
        s << "\n  subtitles:"
        t.subtitles().each do |e|
          s << "\n    #{e}"
        end
        s << "\n  chapters:"
        t.chapters().each do |c|
          s << "\n    #{c}"
        end
      end
      s
    end
  
    def to_s
      size = nil
      if File.file?(path)
        size = ", size=#{Tools::FileTool::humanReadableSize(Tools::FileTool::size(path) || 0)}"
      end
      return "#{path} (title=#{title}, title_alt=#{title_alt}, name=#{name()}#{size})"
    end
  end
  
  class ValueMatcher
    attr_accessor :allowed, :onlyFirstPerAllowedValue
    def initialize(allowed)
      @allowed = allowed || ["*"]
      @onlyFirstPerAllowedValue = false
    end
    
    def check(obj)
      return true
    end
  
    def value(obj)
      raise "method not implemented"
    end
  
    def matches(obj)
      m = (allowed().nil? or allowed().include?("*") or allowed().include?(value(obj)))
      m = false if not check(obj)
      HandbrakeCLI::logger.debug("#{self.class().name()}: #{value(obj).inspect} is allowed (#{allowed.inspect()})? -> #{m}")
      return m
    end
  
    def filter(list)
      return list if allowed().nil?

      filtered = []
      stack = []
      allowed().each do |a|
        list.each do |e|
          # element does not match
          next if not matches(e)
          v = value(e)
          # element already included
          next if (@onlyFirstPerAllowedValue and stack.include?(v)) or filtered.include?(e)
          if v == a or v.eql? a or a.eql? "*"
            # element matches
            stack.push v
            filtered.push e
          end
        end
      end
      return filtered
    end
  
    def to_s
      "#{@allowed}"
    end
  end
  
  class PosMatcher < ValueMatcher
    def value(obj)
      return obj.pos
    end
  end
  
  class LangMatcher < ValueMatcher
    attr_accessor :skipCommentaries, :skipForced
    skipCommentaries = false
    skipForced = false
  
    def value(obj)
      obj.lang
    end
  
    def check(obj)
      return false if @skipCommentaries and obj.commentary?
      return false if @skipForced and obj.forced?
      return true
    end
  end
  
  module_function
  def logger
    @logger ||= Tools::Loggers::createLogger()
  end
  def logger=(l)
    @logger.close if @logger
    @logger = l
  end
end
