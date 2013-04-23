#!/usr/bin/ruby

require 'optparse'
require 'logger'
require './lib/hb_lib.rb'
include HandbrakeCLI

Signal.trap("INT") do
  puts "CTRL-C detected - exiting #{File.basename($0)}"
  exit!(1)
end

def showUsageAndExit(options, msg = nil)
  puts options.to_s
  puts
  puts "available place-holders for output-file:"
  puts "  #pos#   - title-number on input-source"
  puts "  #size#  - resolution"
  puts "  #fps#   - frames per second"
  puts "  #ts#    - current timestamp"
  puts "  #title# - source-title (dvd-label, directory-basename, filename)"
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

options = HandbrakeCLI::HBOptions.new

wait_timeout = -1
loops = 1

ARGV.options do |opts|
  opts.separator("")
  opts.separator("files")
  opts.on("--input INPUT", "input-source") { |arg| options.input = arg }
  opts.on("--output OUTPUT", "output-file (mp4, m4v and mkv supported)") { |arg| options.output = arg }
  opts.on("--force", "force override of existing files") { |arg| options.force = arg }
  opts.on("--loops LOOPS", "processes input LOOPS times (default: 1)") { |arg| loops = arg.to_i }
  opts.on("--input-done-cmd COMMAND", "runs COMMAND after input was processed (use #input# as placeholder)") { |arg| options.inputDoneCommand = arg }
  opts.on("--output-done-cmd COMMAND", "runs COMMAND after an output-file was generated (use #output# as placeholder)") { |arg| options.outputDoneCommand = arg }
  opts.on("--wait-timeout SECONDS", "waits SECONDS seconds until input exists (default: unlimited)") { |arg| wait_timeout = arg.to_i }
  opts.on("--check", "show only available titles and tracks") { |arg| options.checkOnly = arg }
  opts.on("--help", "Display this screen") { |arg| showUsageAndExit(opts.to_s) }

  opts.separator("")
  opts.separator("output-options")
  opts.on("--compatibility", "enables iPod compatible output (only m4v and mp4)") { |arg| options.ipodCompatibility = arg }
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
  opts.on("--preset PRESET", "the handbrake-preset to use (#{Handbrake::getPresets().keys.join(', ')})") { |arg| options.preset = arg }
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
  opts.separator("expert-options")
  opts.on("--xtra ARGS", "additional arguments for handbrake") { |arg| options.xtra_args = arg }
  opts.on("--debug", "enable debug-mode (doesn't start conversion)") { |arg| options.debug = arg }
  opts.on("--verbose", "enable verbose output") { |arg| options.verbose = arg }
  opts.on("--testdata FILE", "read info from/write info to file") { |arg| options.testdata = arg }
  opts.on("--x264-profile PRESET", "use x264-profile (#{Handbrake::X264_PROFILES.join(', ')})") { |arg| options.x264profile = arg }
  opts.on("--x264-preset PRESET", "use x264-preset (#{Handbrake::X264_PRESETS.join(', ')})") { |arg| options.x264preset = arg }
  opts.on("--x264-tune OPTION", "tune x264 (#{Handbrake::X264_TUNES.join(', ')})") { |arg| options.x264tune = arg }
    
  def setdefaults(options)
    options.languages = ["deu", "eng"]
    options.subtitles = ["deu", "eng"]
    options.onlyFirstTrackPerLanguage = true
    options.audioCopy = true
    options.skipCommentaries = true
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
end

begin
  ARGV.parse!
rescue => e
  if not e.kind_of?(SystemExit)
    showUsageAndExit(ARGV.options, e.to_s)
  else
    exit
  end
end

# set default values
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
   showUsageAndExit(options,"""handbrake not found
download Handbrake CLI at http://handbrake.fr/downloads2.php for your platform
and copy the application-files to #{File::dirname(Handbrake::HANDBRAKE_CLI)}
""")
end

if options.verbose and options.debug
  Tools::CON.level = Logger::DEBUG
elsif options.verbose or options.debug
  Tools::CON.level = Logger::INFO
else
  Tools::CON.level = Logger::WARN
end

# check settings
showUsageAndExit(ARGV.options, "input not set") if options.input.nil?()
showUsageAndExit(ARGV.options, "output not set") if not options.checkOnly and options.output.nil?()
#showUsageAndExit(ARGV.options, "\"#{options.input}\" does not exist") if not File.exists? options.input
showUsageAndExit(ARGV.options,"unknown x264-profile: #{options.x264profile}") if not options.x264profile.nil? and not Handbrake::X264_PROFILES.include?(options.x264profile)
showUsageAndExit(ARGV.options,"unknown x264-preset: #{options.x264preset}") if not options.x264preset.nil? and not Handbrake::X264_PRESETS.include?(options.x264preset)
showUsageAndExit(ARGV.options,"unknown x264-tune option: #{options.x264tune}") if not options.x264tune.nil? and not Handbrake::X264_TUNES.include?(options.x264tune)
showUsageAndExit(ARGV.options,"unknown audio-encoder: #{options.audioMixdownEncoder}") if not options.audioMixdownEncoder.nil? and not Handbrake::AUDIO_ENCODERS.include?(options.audioMixdownEncoder)
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

titleMatcher = PosMatcher.new(options.titles)
audioMatcher = LangMatcher.new(options.languages)
audioMatcher.onlyFirstPerAllowedValue = options.onlyFirstTrackPerLanguage
audioMatcher.skipCommentaries = options.skipCommentaries
subtitleMatcher = LangMatcher.new(options.subtitles)
subtitleMatcher.skipCommentaries = options.skipCommentaries

# collect all inputs
input_list = [options.input]
input_list += ARGV if not ARGV.empty?

# check each argument
inputs = []
input_list.each do |i|
  if i.include? "*"
    # argument contains a wildcard try to get all files
    files = Dir[i]
    if files.empty?
      puts "found no files for pattern #{i}"
    else
      inputs += files
    end
  else
    # argument can be used directly
    inputs << i
  end
end

inout = []
current_loop = loops
while current_loop != 0
  inputs.each do |input|
    opts = options.dup
    opts.input = input
    unless Tools::FileTool::waitfor(opts.input, wait_timeout, "waiting for #{opts.input}...")
      puts "#{opts.input} does not exist"
      next
    end
    puts "processing #{opts.input}..."
    files = Handbrake::convert(opts, titleMatcher, audioMatcher, subtitleMatcher)
    inout << [input, files]
  end
  current_loop -= 1
end

puts "overview"
inout.each do |input,outputs|
  puts "#{input}"
  if outputs.empty?
    puts "  -> n/a"
  else
    outputs.each{|file| puts "  -> #{file}"}
  end
end
