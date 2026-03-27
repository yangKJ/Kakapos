#!/bin/bash

# 视频延时摄影脚本
# 用法: ./video_time_lapse.sh input_file output_file [speed_factor]

if [ $# -lt 2 ]; then
    echo "用法: ./video_time_lapse.sh input_file output_file [speed_factor]"
    echo "示例: ./video_time_lapse.sh input.mp4 output.mp4"
    echo "示例: ./video_time_lapse.sh input.mp4 output.mp4 10"
    exit 1
fi

INPUT="$1"
OUTPUT="$2"
SPEED_FACTOR="${3:-5}"

echo "正在为视频 $INPUT 创建延时摄影效果，速度因子: $SPEED_FACTOR..."

# 使用ffmpeg创建延时摄影效果
ffmpeg -i "$INPUT" -filter_complex "[0:v]setpts=1/${SPEED_FACTOR}*PTS[v];[0:a]atempo=${SPEED_FACTOR}[a]" -map "[v]" -map "[a]" -c:v libx264 -preset medium -crf 23 -c:a aac -b:a 128k "$OUTPUT"

if [ $? -eq 0 ]; then
    echo "延时摄影效果创建成功! 输出文件: $OUTPUT"
else
    echo "延时摄影效果创建失败!"
    exit 1
fi