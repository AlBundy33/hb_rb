require 'fileutils'
require 'optparse'
begin
  require File.join(File.dirname(__FILE__), "manicure.rb")
  CAN_LOAD_PLIST = true
rescue LoadError
  CAN_LOAD_PLIST = false
end
require File.join(File.dirname(__FILE__), "tools.rb")
require File.join(File.dirname(__FILE__), "commands.rb")

module HandbrakeCLI
  class HBConvertResult
    attr_accessor :command, :file, :source, :title, :audiotitles, :subtitles, :output
  end
  class HBOptions
    attr_accessor :input, :output, :force,
                  :ipodCompatibility, :enableAutocrop,
                  :languages, :audioMixdown, :audioCopy,
                  :audioMixdownEncoder, :audioMixdownBitrate, :audioMixdownMappings,
                  :maxHeight, :maxWidth, :subtitles, :preset, :mainFeatureOnly, :titles, :chapters,
                  :minLength, :maxLength, :skipDuplicates,
                  :onlyFirstTrackPerLanguage, :skipCommentaries,
                  :checkOnly, :xtra_args, :debug, :verbose,
                  :x264profile, :x264preset, :x264tune,
                  :testdata, :preview, :inputWaitLoops, :loops,
                  :logfile, :logOverride, :logOverview,
                  :inputDoneCommands, :outputDoneCommands, :bluray

    def self.showUsageAndExit(options, msg = nil)
      puts options.to_s
      puts
      puts "available place-holders for output-file:"
      puts "  #pos#             - title-number on input-source"
      puts "  #size#            - resolution"
      puts "  #fps#             - frames per second"
      puts "  #ts#              - current timestamp"
      puts "  #title#           - source-title (dvd-label, directory-basename, filename)"
      puts "  #source#          - name of input"
      puts "  #source_basename# - name of input without extension"
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
      puts "convert complete file with own mixdowns (copy 5.1 and Dolby Surround, mixdown 2.0 to stereo and 1.0 to mono)"
      puts "#{File.basename($0)} --input /dev/rdisk1 --output \"~/Output_#pos#.m4v\" --audio-mixdown \"5.1:copy,1.0:mono,2.0:stereo,Dolby Surround:copy\""
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
    
    def self.setdefaults(options)
      options.languages = ["deu", "eng"]
      options.subtitles = ["deu", "eng"]
      options.onlyFirstTrackPerLanguage = true
      options.audioCopy = true
      options.skipCommentaries = true
    end

    def self.parseArgs(arguments)
      options = HBOptions.new
      options.inputDoneCommands = []
      options.outputDoneCommands= []
      optparse = OptionParser.new do |opts|
        opts.separator("")
        opts.separator("common")
        opts.on("--input INPUT", "input-source") { |arg| options.input = arg }
        opts.on("--output OUTPUT", "output-file (mp4, m4v and mkv supported)") { |arg| options.output = arg }
        opts.on("--force", "force override of existing files") { |arg| options.force = arg }
        opts.on("--check", "show only available titles and tracks") { |arg| options.checkOnly = arg }
        opts.on("--help", "Display this screen") { |arg| showUsageAndExit(opts) }

        opts.separator("")
        opts.separator("output-options")
        opts.on("--compatibility", "enables iPod compatible output (only m4v and mp4)") { |arg| options.ipodCompatibility = arg }
        opts.on("--bluray", "disables decomb and enables support for mp4-files over 4GB") { |arg| options.bluray = arg }
        opts.on("--autocrop", "automatically crop black bars") { |arg| options.enableAutocrop = arg }
        opts.on("--max-height HEIGTH", "maximum video height (e.g. 720, 1080)") { |arg| options.maxHeight = arg }
        opts.on("--max-width WIDTH", "maximum video width (e.g. 1920)") { |arg| options.maxWidth = arg }
        opts.on("--audio LANGUAGES", Array, "the audio languages") { |arg| options.languages = arg }
        opts.on("--audio-copy", "add original-audio track") { |arg| options.audioCopy = arg }
        opts.on("--audio-mixdown [MAPPINGS]", Array, "add mixed down track. Use optional MAPPINGS to define the mixdown per track description (default: dpl2, allowed: #{(["copy"] + Handbrake::AUDIO_MIXDOWNS).join(', ')})") { |arg| 
            options.audioMixdown = true
            options.audioMixdownMappings = arg 
        }
        opts.on("--audio-mixdown-encoder ENCODER", "add encoded audio track (#{Handbrake::AUDIO_ENCODERS.join(', ')})") { |arg| options.audioMixdownEncoder = arg }
        opts.on("--audio-mixdown-bitrate BITRATE", "bitrate for encoded audio track (default 160kb/s)") { |arg| options.audioMixdownBitrate = arg }
        opts.on("--subtitles LANGUAGES", Array, "the subtitle languages") { |arg| options.subtitles = arg }
        opts.on("--preset PRESET", "the handbrake-preset to use (#{Handbrake::getPresets().keys.sort.join(', ')})") { |arg| options.preset = arg }
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
          
        opts.separator("")
        opts.separator("logging")
        opts.on("--log [LOGFILE]", "write all output to LOGFILE") { |arg| options.logfile = arg || "hb.log" }
        opts.on("--log-override", "always override logfile") { |arg| options.logOverride = arg }
        opts.on("--log-overview LOGFILE", "write additional overview-file") { |arg| options.logOverview = arg }
      
        opts.separator("")
        opts.separator("expert-options")
        opts.on("--loops LOOPS", "processes input LOOPS times (default: 1)") { |arg| options.loops = arg.to_i }
        opts.on("--wait LOOPS", "retries LOOPS times to wait for input (default: unlimited)") { |arg| options.inputWaitLoops = arg.to_i }
        opts.on("--xtra ARGS", "additional arguments for handbrake") { |arg| options.xtra_args = arg }
        opts.on("--debug", "enable debug-mode (doesn't start conversion)") { |arg| options.debug = arg }
        opts.on("--verbose", "enable verbose output") { |arg| options.verbose = arg }
        opts.on("--testdata FILE", "read info from/write info to file") { |arg| options.testdata = arg }
        opts.on("--x264-profile PRESET", "use x264-profile (#{Handbrake::X264_PROFILES.join(', ')})") { |arg| options.x264profile = arg }
        opts.on("--x264-preset PRESET", "use x264-preset (#{Handbrake::X264_PRESETS.join(', ')})") { |arg| options.x264preset = arg }
        opts.on("--x264-tune OPTION", "tune x264 (#{Handbrake::X264_TUNES.join(', ')})") { |arg| options.x264tune = arg }

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
      
        opts.separator("")
        opts.separator("shorts")
        opts.on("--default",   "sets: --audio deu,eng --subtitles deu,eng --audio-copy --skip-commentaries --only-first-track-per-language") do |arg|
          setdefaults(options)
        end
        opts.on("--movie",   "sets: --default --main") do |arg|
          setdefaults(options)
          options.mainFeatureOnly = true
        end
        opts.on("--episodes", "sets: --default --min-length 00:10:00 --max-length 00:50:00 --skip-duplicates") do |arg|
          setdefaults(options)
          options.minLength = "00:10:00"
          options.maxLength = "00:50:00"
          options.skipDuplicates = true
        end
        opts.on("--lang LANGUAGES", Array, "set subtitle and audio languges") do |arg|
          options.languages = arg
          options.subtitles = arg
        end
      end
      
      begin
        optparse.parse!(arguments)
      rescue => e
        if not e.kind_of?(SystemExit)
          showUsageAndExit(optparse, e.to_s)
        else
          exit
        end
      end
      
      # set default values
      options.inputWaitLoops = -1 if options.inputWaitLoops.nil?
      options.loops = 1 if options.loops.nil?
      options.force = false if options.force.nil?
      options.ipodCompatibility = false if options.ipodCompatibility.nil?
      options.enableAutocrop = false if options.enableAutocrop.nil?
      options.audioCopy = true if options.audioMixdown.nil? and options.audioCopy.nil?
      options.mainFeatureOnly = false if options.mainFeatureOnly.nil?
      options.skipDuplicates = false if options.skipDuplicates.nil?
      options.onlyFirstTrackPerLanguage = false if options.onlyFirstTrackPerLanguage.nil?
      options.skipCommentaries = false if options.skipCommentaries.nil?
      options.checkOnly = false if options.checkOnly.nil?
      options.debug = false if options.debug.nil?
      options.verbose = false if options.verbose.nil?
      options.titles.collect!{ |t| t.to_i } if not options.titles.nil?
      options.audioMixdownBitrate = "160" if options.audioMixdownBitrate.nil?
      
      if not Tools::OS::command2?(Handbrake::HANDBRAKE_CLI)
         showUsageAndExit(optparse,"""handbrake not found
      download Handbrake CLI at http://handbrake.fr/downloads2.php for your platform
      and copy the application-files to #{File::dirname(Handbrake::HANDBRAKE_CLI)}
      """)
      end
      
      # check settings
      showUsageAndExit(optparse, "input not set") if options.input.nil?()
      showUsageAndExit(optparse, "output not set") if not options.checkOnly and options.output.nil?()
      #showUsageAndExit(optparse, "\"#{options.input}\" does not exist") if not File.exists? options.input
      showUsageAndExit(optparse,"unknown x264-profile: #{options.x264profile}") if not options.x264profile.nil? and not Handbrake::X264_PROFILES.include?(options.x264profile)
      showUsageAndExit(optparse,"unknown x264-preset: #{options.x264preset}") if not options.x264preset.nil? and not Handbrake::X264_PRESETS.include?(options.x264preset)
      showUsageAndExit(optparse,"unknown x264-tune option: #{options.x264tune}") if not options.x264tune.nil? and not Handbrake::X264_TUNES.include?(options.x264tune)
      showUsageAndExit(optparse,"unknown audio-encoder: #{options.audioMixdownEncoder}") if not options.audioMixdownEncoder.nil? and not Handbrake::AUDIO_ENCODERS.include?(options.audioMixdownEncoder)
      if not options.audioMixdownMappings.nil?
        h = {}
        allowed = ["copy"] + Handbrake::AUDIO_MIXDOWNS
        options.audioMixdownMappings.each do |m|
          a = m.split(":", 2)
          showUsageAndExit(options,"unknon mixdown option #{a.last} (allowed: #{allowed.join(', ')})") if not allowed.include?(a.last)
          h[a.first] = a.last
        end
        options.audioMixdownMappings = h
      end
      showUsageAndExit(options,"unknown preset #{options.preset}") if not options.preset.nil? and Handbrake::getPresets()[options.preset].nil?
      return options
    end
  end

  class Handbrake
    include Tools

    HANDBRAKE_CLI = File.expand_path("#{File.dirname(__FILE__)}/../tools/handbrake/#{Tools::OS::platform().to_s.downcase}/HandBrakeCLI")
  
    AUDIO_ENCODERS = %w(ca_aac ca_haac faac ffaac ffac3 lame vorbis ffflac)
    AUDIO_MIXDOWNS = %w(mono stereo dpl1 dpl2 6ch)
    AUDIO_MIXDOWN_DESCR = {
      "mono" => "Mono",
      "stereo" => "Stereo",
      "dpl1" => "Dolby Surround",
      "dpl2" => "Dolby Pro Logic II",
      "6ch" => "5.1"
    }
  
    X264_PROFILES = %w(baseline main high high10 high422 high444)
    X264_PRESETS = %w(ultrafast superfast veryfast faster fast medium slow slower veryslow placebo)
    X264_TUNES = %w(film animation grain stillimage psnr ssim fastdecode zerolatency)
  
    def self.getPresets()
      result = {}
      mergeHash(result, loadBuiltInPresets())
      Dir.glob(File.join(File.dirname($0), "*.plist")) do |f|
        mergeHash(result, loadPlist(File.expand_path(f)))
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
        mergeHash(result, parsePresets(DisplayToString.new(plist, options).output))
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
  
    def self.readInfo(input, debug = false, testdata = nil)
      path = File.expand_path(input)

      cmd = "\"#{HANDBRAKE_CLI}\" -i \"#{path}\" --scan --title 0 2>&1"
      if !testdata.nil? and File.exists?(testdata)
        output = File.read(testdata)
      else
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
        puts "out> #{line}" if debug
  
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
      
      source.title = getTitle(path) if source.title.nil?()
      
      return source
    end
    
    def self.getTitle(path)
      if Tools::OS::platform?(Tools::OS::WINDOWS)
        if path.length < 4 and path[1] == ?:
          output = %x[vol #{path[0..1]}]
          idx = -1
          tokens = []
          output.lines.first().split.each do |t|
            idx += 1 if t.upcase.eql?(path[0].chr.upcase) or t.upcase.eql?(path[0..1].upcase) or idx >= 0
            tokens << t if idx > 1
          end
          return tokens.join(" ")
        else
          return File.basename(path)
        end
      end
      return nil
    end
    
    def self.getMixdown(track, mappings, default)
      descr = "#{track.descr}"
      if not mappings.nil?
        mappings.each do |r,m|
          return m if descr =~ /#{r}/
        end
      end
      return default
    end
  
    def self.convert(options, titleMatcher, audioMatcher, subtitleMatcher)
      source = Handbrake::readInfo(options.input, options.debug && options.verbose, options.testdata)
      created = []
      if options.checkOnly
        puts source.info
        return created
      end
      
      if source.titles.empty?
        HandbrakeCLI::logger.info("#{source.path} contains no titles")
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
  
      HandbrakeCLI::logger.warn("#{source}")
      source.titles().each do |title|
        HandbrakeCLI::logger.info("checking #{title}")
        
        if options.mainFeatureOnly and not title.mainFeature
          HandbrakeCLI::logger.info("skipping title because it's not the main-feature")
          next
        elsif not titleMatcher.matches(title)
          HandbrakeCLI::logger.info("skipping unwanted title")
          next
        end
        tracks = audioMatcher.filter(title.audioTracks)
        subtitles = subtitleMatcher.filter(title.subtitles)
        
        duration = TimeTool::timeToSeconds(title.duration)
        if minLength >= 0 and duration < minLength
          HandbrakeCLI::logger.info("skipping title because it's duration is too short (#{TimeTool::secondsToTime(minLength)} <= #{TimeTool::secondsToTime(duration)} <= #{TimeTool::secondsToTime(maxLength)})")
          next
        end
        if maxLength >= 0 and duration > maxLength
          HandbrakeCLI::logger.info("skipping title because it's duration is too long (#{TimeTool::secondsToTime(minLength)} <= #{TimeTool::secondsToTime(duration)} <= #{TimeTool::secondsToTime(maxLength)})")
          next
        end
        if tracks.empty?()
          HandbrakeCLI::logger.info("skipping title because it contains no audio-tracks (available: #{title.audioTracks})")
          next
        end
        if options.skipDuplicates and not title.blocks().nil? and title.blocks() >= 0 and converted.include?(title.blocks())
          HandbrakeCLI::logger.info("skipping because source contains it twice")
          next
        end
        
        converted.push(title.blocks()) if not title.blocks().nil?

        result = HBConvertResult.new
        result.source = source
        result.title = title
        result.audiotitles = tracks
        result.subtitles = subtitles
  
        outputFile = File.expand_path(options.output)
        source_title = source.name.gsub(/[^0-9a-zA-Z_\- ]/, "_")
        outputFile.gsub!("#pos#", "%02d" % title.pos)
        outputFile.gsub!("#size#", title.size || "")
        outputFile.gsub!("#fps#", title.fps || "")
        outputFile.gsub!("#ts#", Time.new.strftime("%Y-%m-%d_%H_%M_%S"))
        outputFile.gsub!("#title#", source_title)
        outputFile.gsub!("#source#", source.input_name(false) || source_title)
        outputFile.gsub!("#source_basename#", source.input_name(true) || source_title)
        if not options.force
          if File.exists?(outputFile) or Dir.glob("#{File.dirname(outputFile)}/*.#{File.basename(outputFile)}").size() > 0
            HandbrakeCLI::logger.warn("skipping title because \"#{outputFile}\" already exists")
            next
          end
        end
  
        HandbrakeCLI::logger.info("converting #{title}")
  
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
          command << " --encoder x264"
          command << " --quality 20.0"
          command << " --decomb" if not options.bluray
          command << " --detelecine"
          command << " --crop 0:0:0:0" if not options.enableAutocrop
          if not options.ipodCompatibility
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
  
        # format
        if ismp4
          command << " --format mp4"
          command << " --optimize"
          command << " --large-file" if options.bluray
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
  
        # audio
        paudio = []
        paencoder = []
        parate = []
        pmixdown = []
        pab = []
        pdrc = []
        paname = []
        
        tracks.each do |t|
          mixdown_track = options.audioMixdown
          copy_track = options.audioCopy
          use_preset_settings = !options.preset.nil?
          mixdown = nil
  
          if mixdown_track
            mixdown = getMixdown(t, options.audioMixdownMappings, "dpl2")
            if mixdown.eql?("copy")
              mixdown = nil
              mixdown_track = false
              copy_track = true
            end
          end
          
          if use_preset_settings
            mixdown_track = false
            copy_track = false
          end
  
          HandbrakeCLI::logger.info("checking audio-track #{t}")
          if use_preset_settings
            value = preset_arguments.match(/(?:-a|--audio) ([^ ]+)/)[1]
            track_count = value.split(",").size
            paudio << ([t.pos] * track_count).join(",")
            value = preset_arguments.match(/(?:-E|--aencoder) ([^ ]+)/)[1]
            paencoder << value unless value.nil?
            value = preset_arguments.match(/(?:-R|--arate) ([^ ]+)/)[1]
            parate << value unless value.nil?
            value = preset_arguments.match(/(?:-6|--mixdown) ([^ ]+)/)[1]
            pmixdown << value unless value.nil?
            value = preset_arguments.match(/(?:-B|--ab) ([^ ]+)/)[1]
            pab << value unless value.nil?
            value = preset_arguments.match(/(?:-D|--drc) ([^ ]+)/)[1]
            pdrc << value unless value.nil?
            paname << (["#{t.descr(true)}"] * track_count).join("\",\"")
            HandbrakeCLI::logger.info("adding audio-track: #{t}")            
          end
          if copy_track
            # copy original track
            paudio << t.pos
            paencoder << "copy"
            parate << "auto"
            pmixdown << "auto"
            pab << "auto"
            pdrc << "0.0"
            paname << "#{t.descr}"
            HandbrakeCLI::logger.info("adding audio-track: #{t}")
          end
          if mixdown_track
            # add mixdown track
            paudio << t.pos
            if not options.audioMixdownEncoder.nil?
              paencoder << options.audioMixdownEncoder
            elsif ismp4
              paencoder << "faac"
            else
              paencoder << "lame"
            end
            parate << "auto"
            pmixdown << mixdown
            pab << options.audioMixdownBitrate
            pdrc << "0.0"
            paname << "#{t.descr(true)} (#{AUDIO_MIXDOWN_DESCR[mixdown] || mixdown})"
            HandbrakeCLI::logger.info("adding mixed down audio-track: #{t}")
          end
        end
        command << " --audio #{paudio.join(',')}"
        command << " --aencoder #{paencoder.join(',')}" unless paencoder.empty?
        command << " --arate #{parate.join(',')}" unless parate.empty?
        command << " --mixdown #{pmixdown.join(',')}" unless pmixdown.empty?
        command << " --ab #{pab.join(',')}" unless pab.empty?
        command << " --drc #{pdrc.join(',')}" unless pdrc.empty?
        command << " --aname \"#{paname.join('","')}\""
        if ismp4
          command << " --audio-fallback faac"
        else
          command << " --audio-fallback lame"
        end
  
        # subtitles
        psubtitles = subtitles.collect{ |s| s.pos }
        command << " --subtitle #{psubtitles.join(',')}" if not psubtitles.empty?()
  
        # arguments to delegate...
        command << " #{options.xtra_args}" if not options.xtra_args.nil?

        if options.verbose
          command << " 2>&1"
        else
          command << " 2>#{Tools::OS::nullDevice()}"
        end
  
        start_time = Time.now
        HandbrakeCLI::logger.warn "input title #{title.pos}#{title.mainFeature ? " (main-feature)" : ""} #{title.duration} #{title.size} (blocks: #{title.blocks()})"
        unless title.audioTracks.empty?
          HandbrakeCLI::logger.warn "  audio-tracks"
          title.audioTracks.each do |t|
            HandbrakeCLI::logger.warn "    - track #{t.pos}: #{t.descr}"
          end
        end
        unless title.subtitles.empty?
          HandbrakeCLI::logger.warn "  subtitles"
          title.subtitles.each do |s|
            HandbrakeCLI::logger.warn "    - track #{s.pos}: #{s.descr}"
          end
        end
        HandbrakeCLI::logger.warn "  == converting to ==" 
        if not tracks.empty?
          HandbrakeCLI::logger.warn "  audio-tracks"
          tracks.each do |t|
            HandbrakeCLI::logger.warn "    - track #{t.pos}: #{t.descr}"
          end
        end
        if not subtitles.empty?
          HandbrakeCLI::logger.warn "  subtitles"
          subtitles.each do |s|
            HandbrakeCLI::logger.warn "    - track #{s.pos}: #{s.descr}"
          end
        end
  
        HandbrakeCLI::logger.warn(command)
        if not options.testdata.nil?
          result.file = outputFile
          result.command = command
          created << result
        elsif not options.debug
          parentDir = File.dirname(outputFile)
          FileUtils.mkdir_p(parentDir) unless File.directory?(parentDir)
          Tools::Loggers::tee(command,HandbrakeCLI::logger)
          return_code = $?
          if File.exists?(outputFile)
            size = Tools::FileTool::size(outputFile)
            if return_code != 0
              HandbrakeCLI::logger.warn("Handbrake exited with return-code #{return_code} - removing file #{File.basename(outputFile)}")
              File.delete(outputFile)
              converted.delete(title.blocks())
            elsif size >= 0 and size < (1 * 1024 * 1024)
              HandbrakeCLI::logger.warn("file-size only #{Tools::FileTool::humanReadableSize(size)} - removing file #{File.basename(outputFile)}")
              File.delete(outputFile)
              converted.delete(title.blocks())
            else
              HandbrakeCLI::logger.warn("file #{outputFile} created (#{Tools::FileTool::humanReadableSize(size)})")
              if size >= 4 * 1024 * 1024 * 1024 and !command =~ /--large-file/
                HandbrakeCLI::logger.warn("file maybe useless because it's over 4GB and --large-file was not specified")
              end
              result.file = outputFile
              result.command = command
              result.output = readInfo(outputFile, false, nil)
              options.outputDoneCommands.each do |command|
                cmd = command.create_command(outputFile)
                if cmd.nil?
                  HandbrakeCLI::logger.info("[#{command}] #{outputFile} (#{command.arg})")
                  command.run(outputFile)
                else
                  HandbrakeCLI::logger.info("[#{command}] #{cmd}")
                  Tools::Loggers::tee(cmd, HandbrakeCLI::logger)
                end
                raise "command #{cmd} failed (return-code: #{$?}" if $? != 0
              end
              created << result
            end
          else
            HandbrakeCLI::logger.warn("file #{outputFile} not created")
          end
        end
        end_time = Time.now
        required_time = Tools::TimeTool::secondsToTime((end_time - start_time).round)
        HandbrakeCLI::logger.warn("== done (required time: #{required_time}) =================================")
      end
      unless created.empty?
        options.inputDoneCommands.each do |command|
          cmd = command.create_command(options.input)
          if cmd.nil?
            HandbrakeCLI::logger.info("[#{command}] #{options.input} (#{command.arg})")
            command.run(options.input)
          else
            HandbrakeCLI::logger.info("[#{command}] #{cmd}")
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
      return true if @descr.downcase().include?("commentary")
      return false
    end
  
    def to_s
      "#{pos}. #{descr} (lang=#{lang}, comment=#{comment}, commentary=#{commentary?()})"
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
    
    def descr(cleaned = false)
      return @descr unless cleaned
      d = @descr.dup
      d.gsub!(/[(]?#{codec}[)]?/, "")
      d.gsub!(/[(]?#{channels}[)]?/, "")
      d.strip!
      return d
    end
  
    def commentary?()
      return true if @descr.downcase().include?("commentary")
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
          name = path[0].chr
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
      "#{path} (title=#{title}, title_alt=#{title_alt}, serial=#{serial}, name=#{name()})"
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
          next if @onlyFirstPerAllowedValue and stack.include?(v)
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
    attr_accessor :skipCommentaries
    skipCommentaries = false
  
    def value(obj)
      obj.lang
    end
  
    def check(obj) 
      return false if @skipCommentaries and obj.commentary?
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
