#!/bin/bash

# 视频提取音频脚本
# 用法: ./video_extract_audio.sh input_file output_file [format]

if [ $# -lt 2 ]; then
    echo "用法: ./video_extract_audio.sh input_file output_file [format]"
    echo "示例: ./video_extract_audio.sh input.mp4 output.mp3"
    echo "示例: ./video_extract_audio.sh input.mp4 output.wav"
    exit 1
fi

INPUT="$1"
OUTPUT="$2"
FORMAT="${3:-mp3}"

echo "正在从 $INPUT 提取音频，输出格式: $FORMAT..."

# 使用ffmpeg提取音频
ffmpeg -i "$INPUT" -q:a 0 -map a "$OUTPUT"

if [ $? -eq 0 ]; then
    echo "提取成功! 输出文件: $OUTPUT"
else
    echo "提取失败!"
    exit 1
fi