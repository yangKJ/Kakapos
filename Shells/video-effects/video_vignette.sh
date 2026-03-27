#!/bin/bash

# 视频暗角效果脚本
# 用法: ./video_vignette.sh input_file output_file [size] [opacity]

if [ $# -lt 2 ]; then
    echo "用法: ./video_vignette.sh input_file output_file [size] [opacity]"
    echo "示例: ./video_vignette.sh input.mp4 output.mp4"
    echo "示例: ./video_vignette.sh input.mp4 output.mp4 0.5 0.8"
    exit 1
fi

INPUT="$1"
OUTPUT="$2"
SIZE="${3:-0.4}"
OPACITY="${4:-0.6}"

echo "正在为视频 $INPUT 添加暗角效果，大小: $SIZE，透明度: $OPACITY..."

# 使用ffmpeg添加暗角效果
ffmpeg -i "$INPUT" -filter_complex "[0:v]vignette=PI/4:$SIZE:$OPACITY" -c:v libx264 -preset medium -crf 23 -c:a copy "$OUTPUT"

if [ $? -eq 0 ]; then
    echo "暗角效果添加成功! 输出文件: $OUTPUT"
else
    echo "暗角效果添加失败!"
    exit 1
fi