@ECHO OFF
SETLOCAL ENABLEEXTENSIONS ENABLEDELAYEDEXPANSION
CHCP 1252
SET "HB_RB=E:\DVD-Rips\ruby %~dp0..\hb.rb"

CALL !HB_RB! --create-encode-log --qsv --input "D:\Video\Rips\*.mkv" --output "d:\Video\#source_basename#.mkv" --movie

PAUSE