require 'test/unit'
require 'logger'
require './lib/tools.rb'
require './lib/hb_lib.rb'
include HandbrakeCLI

class ToolTest < Test::Unit::TestCase
  def test_default()
    args = %w(--input /dev/null --output /tmp/tmp.m4v --testdata ./test/greenhornet.txt)
    results = get_results(args)
    results.each do |r|
      puts "command    : #{r.command}"
      puts "file       : #{r.file}"
      puts "title      : #{r.title}"
      puts "audiotitles: #{r.audiotitles.join(', ')}"
      puts "subtitles  : #{r.subtitles.join(', ')}"
      puts
    end
  end
  
  def get_results(args)
    options = HandbrakeCLI::HBOptions.parseArgs(args)
    HandbrakeCLI::logger.level = Logger::FATAL
    titleMatcher = PosMatcher.new(options.titles)
    audioMatcher = LangMatcher.new(options.languages)
    audioMatcher.onlyFirstPerAllowedValue = options.onlyFirstTrackPerLanguage
    audioMatcher.skipCommentaries = options.skipCommentaries
    subtitleMatcher = LangMatcher.new(options.subtitles)
    subtitleMatcher.skipCommentaries = options.skipCommentaries
    return HandbrakeCLI::Handbrake::convert(options,titleMatcher,audioMatcher,subtitleMatcher)
  end
end