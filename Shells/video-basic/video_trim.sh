#!/bin/bash

# 视频剪辑脚本
# 用法: ./video_trim.sh input_file output_file start_time duration

if [ $# -lt 4 ]; then
    echo "用法: ./video_trim.sh input_file output_file start_time duration"
    echo "示例: ./video_trim.sh input.mp4 output.mp4 00:00:10 00:00:20"
    echo "示例: ./video_trim.sh input.mp4 output.mp4 10 20"
    exit 1
fi

INPUT="$1"
OUTPUT="$2"
START_TIME="$3"
DURATION="$4"

echo "正在从 $INPUT 剪辑视频，从 $START_TIME 开始，持续 $DURATION..."

# 使用ffmpeg进行剪辑
ffmpeg -i "$INPUT" -ss "$START_TIME" -t "$DURATION" -c copy "$OUTPUT"

if [ $? -eq 0 ]; then
    echo "剪辑成功! 输出文件: $OUTPUT"
else
    echo "剪辑失败!"
    exit 1
fi