#!/bin/bash

# 视频压缩和调整尺寸脚本
# 用法: ./video_compress.sh input_file output_file [width] [height] [quality]

if [ $# -lt 2 ]; then
    echo "用法: ./video_compress.sh input_file output_file [width] [height] [quality]"
    echo "示例: ./video_compress.sh input.mp4 output.mp4 1280 720 23"
    echo "示例: ./video_compress.sh input.mp4 output.mp4"
    exit 1
fi

INPUT="$1"
OUTPUT="$2"
WIDTH="${3:-1280}"
HEIGHT="${4:-720}"
QUALITY="${5:-23}"

echo "正在压缩视频 $INPUT，输出尺寸: ${WIDTH}x${HEIGHT}，质量: $QUALITY..."

# 使用ffmpeg进行压缩和调整尺寸
ffmpeg -i "$INPUT" -vf "scale=$WIDTH:$HEIGHT" -c:v libx264 -preset medium -crf $QUALITY -c:a aac -b:a 128k "$OUTPUT"

if [ $? -eq 0 ]; then
    echo "压缩成功! 输出文件: $OUTPUT"
else
    echo "压缩失败!"
    exit 1
fi