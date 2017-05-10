hb.rb is a "simple" ruby-script to add some more features to HandbrakeCLI.

Main advantages of the script are:
- no need to work with audio-track-numbers - simply use "deu", "eng", etc. to specifiy the wanted language(s)
- filter tracks by duration (e.g. to convert all episodes from a dvd)
- prevent tracks from converting twice
- works with single-files, DVDs and with blurays
- recursive converting
- works also with presets (plist and own presets)


requirements
============
To run hb.rb you need an installed ruby-interpreter.
You can get the current version of ruby for your platfrom from http://www.ruby-lang.org/

installation
============
1. download the latest version from https://github.com/AlBundy33/hb_rb/tree/master/build
2. extract the archive
3. download Handbrake CLI for your platform from http://handbrake.fr/downloads2.php  
4. extract/install Hanbrake CLI to the appropriate folder in hb.rb-installation-folder under tools/handbrake (e.g. HandbrakeCLI.exe to tools/handbrake/windows)
5. repeat step 4 for AtomicParsley and/or Subler if you want to tag your files with tag_epsiodes.rb
6. if you want to work with presets in plist-files you have to install this gem<br>
   ```gem install plist```
7. if you want to use tag_episodes.rb you have to install some gems with following commands<br>
   ```gem install hpricot```<br>
   ```gem install imdb```
8. if you use a ruby-version < 1.9.0 you'll get an error-message when loading imdb - in that case simply open series.rb (path is in stacktrace) and add a \ at the end of line 18
   
run
===
Now you should be able to run hb.rb.
Maybe directly via ./hb.rb or via path_to_ruby/ruby.exe hb.rb

To get a list of possible options and example-calls run hb.rb without any arguments or with --help.

For any questions about hb.rb use also this thread https://forum.handbrake.fr/viewtopic.php?f=10&t=26163

convert main-feature with all original-tracks (audio and subtitle) for languages german and english (override languages with --lang)<br>
```hb.rb --input /dev/rdisk1 --output "~/Movie.m4v" --movie```

convert all episodes with all original-tracks (audio and subtitle) for languages german and english<br>
```hb.rb --input /dev/rdisk1 --output "~/Series_SeasonX_#pos#.m4v" --episodes```

convert complete file or DVD with all tracks, languages etc.<br>
```hb.rb --input /dev/rdisk1 --output "~/Output_#pos#.m4v"```

convert all MKVs recursive in a directory<br>
```hb.rb --input "~/MKV/**/*.mkv" --output "~/#title#.m4v"```

tag and or rename converted files
=================================
If your ripped files are orderd e.g. for According to Jim Season 1

ATJ_S1D1T2.m4v (season 1, disc 1, title 2)<br>
ATJ_S1D1T3.m4v (season 1, disc 1, title 3)<br>
...<br>

you can run

```tag_episode.rb --id Accordingtojim --season 1 --episode 1 --tag --rename ATJ_S1*.m4v```

So the first file will have the name and tags for episode 1, the second file for episode 2 and so on. 

license
=======
This program comes with ABSOLUTELY NO WARRANTY; for details see LICENSE.txt (available in archive).
This is free software, and you are welcome to redistribute it under certain conditions.
