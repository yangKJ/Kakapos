#!/bin/bash

# 视频音频替换脚本
# 用法: ./video_audio_replace.sh input_video input_audio output_file [audio_volume]

if [ $# -lt 3 ]; then
    echo "用法: ./video_audio_replace.sh input_video input_audio output_file [audio_volume]"
    echo "示例: ./video_audio_replace.sh input.mp4 audio.mp3 output.mp4"
    echo "示例: ./video_audio_replace.sh input.mp4 audio.mp3 output.mp4 0.8"
    exit 1
fi

VIDEO="$1"
AUDIO="$2"
OUTPUT="$3"
VOLUME="${4:-1.0}"

echo "正在替换视频 $VIDEO 的音频为 $AUDIO，音量: $VOLUME..."

# 使用ffmpeg替换音频
ffmpeg -i "$VIDEO" -i "$AUDIO" -filter_complex "[1:a]volume=$VOLUME[a]" -map 0:v -map "[a]" -c:v copy -c:a aac -b:a 128k -shortest "$OUTPUT"

if [ $? -eq 0 ]; then
    echo "音频替换成功! 输出文件: $OUTPUT"
else
    echo "音频替换失败!"
    exit 1
fi