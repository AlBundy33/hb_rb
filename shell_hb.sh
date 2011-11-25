#!/bin/bash

CLI=./HandbrakeCLI

INPUT=
OUTPUT=~/Movies
TITLE=
LANG=deu
SKIP=0
EXT=mp4

#PRESET=Universal
#PRESET=iPod
#PRESET=iPhone & iPod Touch
#PRESET=iPhone 4
#PRESET=iPad
#PRESET=AppleTV
#PRESET=AppleTV 2
PRESET=Normal
#PRESET=High Profile
#PRESET=Classic
#PRESET=AppleTV Legacy
#PRESET=iPhone Legacy
#PRESET=iPod Legacy

trap handle_ctrl_c INT
function handle_ctrl_c()
{
    exit 1
}

function show_usage()
{
    echo usage: $(basename $0)
    if [[ ! -z $1 ]]
    then
    	echo ""
    	echo $1
    fi
}

function get_audio_track()
{
	local TRACK=
	local LINE=$($CLI -i "$INPUT" --scan -t $1 2>&1 | grep -A 8 "audio tracks:" | grep -i "iso639-2: $2.*bps")
	TRACK=$(echo $LINE | awk '{print $2}')
	echo $TRACK | tr -d ,
}

while getopts "hi:o:p:t:is:l:" OPTION
do
    case $OPTION in
    	l)
    		LANG=$OPTARG
    		;;
        i)
            INPUT=$OPTARG
            ;;
        o)
            OUTPUT=$OPTARG
            ;;
        t)
            TITLE=$OPTARG
            ;;
        s)
            SKIP=$OPTARG
            ;;
        p) 
            PRESET=$OPTARG
            ;;
        h)
            show_usage
            exit
            ;;
        ?)
            show_usage "unknown argument: $OPTION"
            exit
            ;;
    esac
done

if [[ -z $TITLE ]]
then
	TITLE=`basename $INPUT`
fi

if [[ -z $INPUT ]] || [[ -z $OUTPUT ]] || [[ -z $TITLE ]] || [[ -z $PRESET ]] || [[ -z $LANG ]]
then
    show_usage
    exit 1
fi

FROM=$[1 + $SKIP]
TO=20

for ((t=$FROM;t<=$TO;t++))
do
    TRACK=$t
    if [ $t -lt 10 ]
    then
        TRACK=0$TRACK
    fi
    OUTPUT_FILE="$OUTPUT/$TITLE-$TRACK.$EXT"
    AUDIO_TRACK=$(get_audio_track $t $LANG)
    if [[ ! -e "$OUTPUT_FILE" ]] && [[ ! -z $AUDIO_TRACK ]]
    then
	    $CLI -i "$INPUT" --preset "$PRESET" -o "$OUTPUT_FILE" -t $t -a $AUDIO_TRACK
    fi
done