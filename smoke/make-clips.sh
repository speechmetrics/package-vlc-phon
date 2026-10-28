#!/usr/bin/env bash
# Generate the short test clips used by the smoke test (needs ffmpeg).
# The clips are committed; re-run only to change them.
set -euo pipefail

cd "$(dirname "$0")/clips"
video="-f lavfi -i testsrc=duration=3:size=320x240:rate=25"
audio="-f lavfi -i sine=frequency=440:duration=3"
x264="-c:v libx264 -preset veryslow -crf 35 -pix_fmt yuv420p"
aac="-c:a aac -b:a 32k"

ffmpeg -loglevel error -y $video $audio $x264 $aac -shortest video.mp4
ffmpeg -loglevel error -y $video $audio $x264 $aac -shortest video.mov
ffmpeg -loglevel error -y $audio -c:a pcm_s16le -ar 16000 -ac 1 audio.wav
ffmpeg -loglevel error -y $audio -c:a libmp3lame -b:a 32k audio.mp3
ffmpeg -loglevel error -y $audio $aac audio.m4a
