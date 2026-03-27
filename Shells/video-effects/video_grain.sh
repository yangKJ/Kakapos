#!/bin/bash

# 视频颗粒效果脚本
# 用法: ./video_grain.sh input_file output_file [grain_amount]

if [ $# -lt 2 ]; then
    echo "用法: ./video_grain.sh input_file output_file [grain_amount]"
    echo "示例: ./video_grain.sh input.mp4 output.mp4"
    echo "示例: ./video_grain.sh input.mp4 output.mp4 0.1"
    exit 1
fi

INPUT="$1"
OUTPUT="$2"
GRAIN_AMOUNT="${3:-0.05}"

echo "正在为视频 $INPUT 添加颗粒效果，颗粒量: $GRAIN_AMOUNT..."

# 使用ffmpeg添加颗粒效果
ffmpeg -i "$INPUT" -filter_complex "[0:v]gblur=sigma=1,noise=c0s=${GRAIN_AMOUNT}:all=1" -c:v libx264 -preset medium -crf 23 -c:a copy "$OUTPUT"

if [ $? -eq 0 ]; then
    echo "颗粒效果添加成功! 输出文件: $OUTPUT"
else
    echo "颗粒效果添加失败!"
    exit 1
fi