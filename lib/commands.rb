#require 'ftools'

class BuiltInCommand

  attr_reader :id, :descr, :cmd, :commandline
  attr_accessor :arg, :arg_descr

  def initialize(id, descr, cmd, commandline, arg_descr = nil)
    @id = id
    @descr = descr
    @cmd = cmd
    @commandline = commandline
    @arg_descr = arg_descr
  end

  def needs_argument?
    not @arg_descr.nil?
  end

  def available?()
    !@cmd.nil? and Tools::OS::command2?(@cmd)
  end
  
  def create_command(file)
    cmd = @commandline.dup
    cmd.gsub!("#file#", "#{file}")
    cmd.gsub!("#arg#", "#{@arg}")
    cmd.gsub!("#cmd#", "#{@cmd}")
    return cmd
  end
  
  def run(file)
    system create_command(file)
  end
  
  def to_s
    self.class.to_s
  end
end

class ScriptCommand < BuiltInCommand
  def initialize(id, descr, arg_descr)
    super(id, descr, nil, nil, arg_descr)
  end
  
  def available?
    return true
  end
  
  def create_command(file)
    return nil
  end
  
  def run(file)
  end
end

class EjectCommand < BuiltInCommand
  def initialize(command, commandline)
    super("eject", "eject tray", command, commandline)
  end
end
=begin
class MoveCommand < ScriptCommand
  def initialize()
    super("move", "moves file to TARGETDIR", "TARGETDIR")
  end
  
  def run(file)
    File.move(file, @arg, false)
  end
end

class DeleteCommand < ScriptCommand
  def initialize()
    super("delete", "deletes file", nil) 
  end
  
  def run(file)
    File.delete(file)
  end
end

class CopyCommand < ScriptCommand
  def initialize()
    super("copy", "copies file to TARGETDIR", "TARGETDIR") 
  end
  
  def run(file)
    File.copy(file, @arg, false)
  end
end
=end

class UserDefinedCommand < BuiltInCommand
  def initialize()
    super("done-cmd", "runs user defined COMMAND (use #file# as placeholder)", nil, nil, "COMMAND") 
  end

  def available?
    return true
  end
  
  def create_command(file)
    @commandline = @arg if @commandline.nil?
    super(file)
  end
end

class InputDoneCommands
  def self.create
    l = []
    l << UserDefinedCommand.new
    #l << MoveCommand.new()
    #l << DeleteCommand.new()
    #l << CopyCommand.new()
    if Tools::OS::osx?()
      l << EjectCommand.new("drutil", '#cmd# tray eject')
    end
    if Tools::OS::platform?(Tools::OS::LINUX)
      l << EjectCommand.new("eject", '#cmd# "#file#"')
    end
    l.reject!{|c| not c.available? }
    return l
  end
end

class OutputDoneCommands
  def self.create
    l = []
    l << UserDefinedCommand.new
    #l << MoveCommand.new()
    #l << CopyCommand.new()
    l.reject!{|c| not c.available? }
    return l
  end 
end