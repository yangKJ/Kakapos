#!/bin/bash

# 视频锐化脚本
# 用法: ./video_sharpen.sh input_file output_file [strength]

if [ $# -lt 2 ]; then
    echo "用法: ./video_sharpen.sh input_file output_file [strength]"
    echo "示例: ./video_sharpen.sh input.mp4 output.mp4"
    echo "示例: ./video_sharpen.sh input.mp4 output.mp4 1.5"
    exit 1
fi

INPUT="$1"
OUTPUT="$2"
STRENGTH="${3:-1.0}"

echo "正在为视频 $INPUT 锐化，强度: $STRENGTH..."

# 使用ffmpeg进行视频锐化
ffmpeg -i "$INPUT" -filter_complex "[0:v]unsharp=5:5:${STRENGTH}:3:3:0.4" -c:v libx264 -preset medium -crf 23 -c:a copy "$OUTPUT"

if [ $? -eq 0 ]; then
    echo "锐化成功! 输出文件: $OUTPUT"
else
    echo "锐化失败!"
    exit 1
fi