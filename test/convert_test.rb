require 'test/unit'
require 'logger'
require File.join(File.dirname(__FILE__), "test_lib.rb")
require File.join(File.dirname(__FILE__), "..", "lib", "tools.rb")
require File.join(File.dirname(__FILE__), "..", "lib", "hb_lib.rb")
include HandbrakeCLI

class ToolTest < AbstractTestCase
  def test_movie()
    results = get_results("greenhornet.txt", "--input", "/dev/null", "--output", "/tmp/tmp.m4v", "--movie")
    assert(results.size == 1, nil)
    check_result(results.first, 1, [2, 1], [2, 1])
  end
end