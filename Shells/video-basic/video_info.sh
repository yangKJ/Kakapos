#!/bin/bash

# 视频信息查看脚本
# 用法: ./video_info.sh input_file

if [ $# -lt 1 ]; then
    echo "用法: ./video_info.sh input_file"
    echo "示例: ./video_info.sh input.mp4"
    exit 1
fi

INPUT="$1"

echo "正在查看视频 $INPUT 的信息..."
echo "===================================="

# 使用ffprobe查看视频信息
ffprobe -v quiet -print_format json -show_format -show_streams "$INPUT"

echo "===================================="
echo "信息查看完成!"
