require 'test/unit'
require 'logger'
require './lib/tools.rb'
require './lib/hb_lib.rb'
require "#{File.dirname(__FILE__)}/test_lib.rb"
include HandbrakeCLI

class ToolTest < AbstractTestCase
  def test_movie()
    results = get_results("greenhornet.txt", "--input", "/dev/null", "--output", "/tmp/tmp.m4v", "--movie")
    assert(results.size == 1, nil)
    check_result(results.first, 1, [2, 1], [2, 1])
  end
end