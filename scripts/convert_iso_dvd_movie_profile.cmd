@ECHO OFF
SETLOCAL ENABLEEXTENSIONS ENABLEDELAYEDEXPANSION
CHCP 1252
SET "HB_RB=E:\DVD-Rips\ruby E:\DVD-Rips\hb\hb.rb"

CALL !HB_RB! --create-encode-log --qsv --movie --input "%~dp0*.iso" --output "d:\Video\#title#.mkv" --min-length 01:00:00 %*

PAUSE