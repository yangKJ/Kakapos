#!/bin/bash

# 视频添加背景音乐脚本
# 用法: ./video_add_audio.sh input_file audio_file output_file [audio_volume]

if [ $# -lt 3 ]; then
    echo "用法: ./video_add_audio.sh input_file audio_file output_file [audio_volume]"
    echo "示例: ./video_add_audio.sh input.mp4 bgm.mp3 output.mp4"
    echo "示例: ./video_add_audio.sh input.mp4 bgm.mp3 output.mp4 0.5"
    exit 1
fi

INPUT="$1"
AUDIO="$2"
OUTPUT="$3"
AUDIO_VOLUME="${4:-0.3}"

echo "正在为 $INPUT 添加背景音乐 $AUDIO，音量: $AUDIO_VOLUME..."

# 使用ffmpeg添加背景音乐
ffmpeg -i "$INPUT" -i "$AUDIO" -filter_complex "[1:a]volume=$AUDIO_VOLUME[a1];[0:a][a1]amix=inputs=2:duration=first:dropout_transition=2" -c:v copy -c:a aac -b:a 128k "$OUTPUT"

if [ $? -eq 0 ]; then
    echo "添加背景音乐成功! 输出文件: $OUTPUT"
else
    echo "添加背景音乐失败!"
    exit 1
fi