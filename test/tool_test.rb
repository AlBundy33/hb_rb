require 'test/unit'
require './lib/tools.rb'

class ToolTest < Test::Unit::TestCase
  def testTimeToSeconds
    data = {
      "00:00:01" => 1,
      "00:01:00" => 60,
      "01:00:00" => 3600,
      "01:01:00" => 3660,
      "01:01:01" => 3661,
      "0:1:0" => 60,
      "1" => 1,
      "1:0" => 60,
      "" => -1,
      nil => -1
    }
    data.each do |input,expected|
      #puts "#{input.inspect} -> #{expected}"
      result = Tools::TimeTool::timeToSeconds(input)
      assert_equal(expected,result,"input: #{input}")
    end
  end
end