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
5. repeat step 4 for AtomicParsley and/or Subler if you want to tag your files with tag_epsiodes.rb
6. if you want to use tag_episodes.rb you have to install some gems with following commands
   gem install hpricot
   gem install imdb
7. if you use a ruby-version < 1.9.0 you'll get an error-message when loading imdb - in that case simply open series.rb (path is in stacktrace) and add a \ at the end of line 18
   
run
===
Now you should be able to run hb.rb.
Maybe directly via ./hb.rb or via path_to_ruby/ruby.exe hb.rb

To get a list of possible options and example-calls run hb.rb without any arguments or with --help.

For any questions about hb.rb use also this thread https://forum.handbrake.fr/viewtopic.php?f=10&t=26163

tag and or rename converted files
=================================
If your ripped files are orderd e.g. for According to Jim Season 1
ATJ_S1D1T2.m4v (season 1, disc 1, title 2)
ATJ_S1D1T3.m4v (season 1, disc 1, title 3)
...
you can run
./tag_episode.rb --id Accordingtojim --season 1 --episode 1 --tag --rename ATJ_S1*.m4v
So the first file will have the name and tags for episode 1, the second file for episode 2 and so on. 

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