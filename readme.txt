requirements
============
To run hb.rb you need an installed ruby-interpreter.
You can get the current version of ruby for your platfrom from http://www.ruby-lang.org/

installation
============
1. download the latest version from https://forum.handbrake.fr/viewtopic.php?f=10&t=26163
2. extract the archive
3. download Handbrake CLI for your platform from http://handbrake.fr/downloads2.php  
4. extract/install Hanbrake CLI to the appropriate folder in hb.rb-installation-folder under tools/handbrake (e.g. HandbrakeCLI.exe to tools/handbrake/windows)
   
run
===
Now you should be able to run hb.rb.
Maybe directly via ./hb.rb or via path_to_ruby/ruby.exe hb.rb

To get a list of possible options and example-calls run hb.rb without any arguments or with --help.

For any questions about hb.rb use also this thread https://forum.handbrake.fr/viewtopic.php?f=10&t=26163

useful commands
===============
restart
OSX    : osascript -e 'tell application "System Events" to restart'
windows: shutdown -r -t 0

sleep
OSX    : osascript -e 'tell application "System Events" to sleep'

showdown
OSX    : osascript -e 'tell application "System Events" to shut down'
windows: shutdown -s -t 0

logoff
OSX    : osascript -e 'tell application "System Events" to log out'
windows: shutdown -l -t 0

eject disc
OSX    : drutil tray eject