#!/bin/bash

# 视频绿幕抠像脚本
# 用法: ./video_color_key.sh input_file background_file output_file [similarity] [blend]

if [ $# -lt 3 ]; then
    echo "用法: ./video_color_key.sh input_file background_file output_file [similarity] [blend]"
    echo "示例: ./video_color_key.sh input.mp4 background.mp4 output.mp4"
    echo "示例: ./video_color_key.sh input.mp4 background.mp4 output.mp4 0.3 0.1"
    exit 1
fi

INPUT="$1"
BACKGROUND="$2"
OUTPUT="$3"
SIMILARITY="${4:-0.2}"
BLEND="${5:-0.1}"

echo "正在为视频 $INPUT 进行绿幕抠像，相似度: $SIMILARITY，混合度: $BLEND..."

# 使用ffmpeg进行绿幕抠像
ffmpeg -i "$INPUT" -i "$BACKGROUND" -filter_complex "[0:v]chromakey=green:$SIMILARITY:$BLEND[fg];[1:v][fg]overlay[out]" -map "[out]" -map 0:a -c:v libx264 -preset medium -crf 23 -c:a copy "$OUTPUT"

if [ $? -eq 0 ]; then
    echo "绿幕抠像成功! 输出文件: $OUTPUT"
else
    echo "绿幕抠像失败!"
    exit 1
fi