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
end

class EjectCommand < BuiltInCommand
  def initialize(command, commandline)
    super("eject", "eject tray", command, commandline)
  end
end

class MoveCommand < BuiltInCommand
  def initialize(command, commandline)
    super("move", "moves file to TARGETDIR", command, commandline, "TARGETDIR")
  end
end

class DeleteCommand < BuiltInCommand
  def initialize(command, commandline)
    super("delete", "deletes file", command, commandline)
  end  
end

class InputDoneCommands
  def self.create
    l = []
    if Tools::OS::osx?() or Tools::OS::platform?(Tools::OS::LINUX)
      l << EjectCommand.new("eject", '#cmd# "#file#"')
      l << MoveCommand.new("mv", '#cmd# "#file#" "#arg#"')
      l << DeleteCommand.new("rm", '#cmd# -rf "#file#"')
    end
    l.reject!{|c| not c.available? }
    return l
  end
end

class OutputDoneCommands
  def self.create
    l = []
    if Tools::OS::osx?()
      l << MoveCommand.new("mv", '#cmd# "#file#" "#arg#"')
    elsif Tools::OS::platform?(Tools::OS::LINUX)
      l << MoveCommand.new("mv", '#cmd# "#file#" "#arg#"')
    end
    l.reject!{|c| not c.available? }
    return l
  end 
end