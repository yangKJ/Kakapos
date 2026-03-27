#!/bin/bash

# 视频格式转换脚本
# 用法: ./video_convert.sh input_file output_file [codec]

if [ $# -lt 2 ]; then
    echo "用法: ./video_convert.sh input_file output_file [codec]"
    echo "示例: ./video_convert.sh input.mp4 output.mov"
    echo "示例: ./video_convert.sh input.mp4 output.mp4 h264"
    exit 1
fi

INPUT="$1"
OUTPUT="$2"
CODEC="${3:-h264}"

echo "正在将 $INPUT 转换为 $OUTPUT，使用编码: $CODEC..."

# 使用ffmpeg进行转换
ffmpeg -i "$INPUT" -c:v $CODEC -preset medium -crf 23 -c:a aac -b:a 128k "$OUTPUT"

if [ $? -eq 0 ]; then
    echo "转换成功! 输出文件: $OUTPUT"
else
    echo "转换失败!"
    exit 1
fi