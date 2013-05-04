require './lib/tools.rb'
require './lib/hb_lib.rb'

class AbstractTestCase < Test::Unit::TestCase
  def get_results(dvd, *args)
    options = HandbrakeCLI::HBOptions.parseArgs(["--testdata", File.join(File.dirname(__FILE__), dvd)] + args)
    HandbrakeCLI::logger.level = log_level()
    titleMatcher = PosMatcher.new(options.titles)
    audioMatcher = LangMatcher.new(options.languages)
    audioMatcher.onlyFirstPerAllowedValue = options.onlyFirstTrackPerLanguage
    audioMatcher.skipCommentaries = options.skipCommentaries
    subtitleMatcher = LangMatcher.new(options.subtitles)
    subtitleMatcher.skipCommentaries = options.skipCommentaries
    return HandbrakeCLI::Handbrake::convert(options,titleMatcher,audioMatcher,subtitleMatcher)
  end
  
  def dump_result(result)
    puts "command    : #{result.command}"
    puts "file       : #{result.file}"
    puts "title      : #{result.title}"
    puts "audiotitles: #{result.audiotitles.join(', ')}"
    puts "subtitles  : #{result.subtitles.join(', ')}"
    puts
  end
  
  def check_result(result, title, audiotitles, subtitles)
    assert_equal(result.title.pos, title)
    assert_equal(
      audiotitles,
      result.audiotitles.collect{|t| t.pos })
    assert_equal(
      subtitles,
      result.subtitles.collect{|t| t.pos })
  end
  
  def log_level
    Logger::FATAL
  end
end