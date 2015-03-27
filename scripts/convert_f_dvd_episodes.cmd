@ECHO OFF
SETLOCAL ENABLEEXTENSIONS ENABLEDELAYEDEXPANSION
CHCP 1252
SET "HB_RB=E:\DVD-Rips\ruby E:\DVD-Rips\hb\hb.rb"

CALL !HB_RB! --create-encode-log --qsv --episodes --hbpreset dvd --input F: --output "d:\Video\Rips\#title#_#pos#.mkv" --input-eject %*

PAUSE