#!/bin/bash

# 视频 glitch 效果脚本
# 用法: ./video_glitch.sh input_file output_file [intensity] [frequency]

if [ $# -lt 2 ]; then
    echo "用法: ./video_glitch.sh input_file output_file [intensity] [frequency]"
    echo "示例: ./video_glitch.sh input.mp4 output.mp4"
    echo "示例: ./video_glitch.sh input.mp4 output.mp4 0.1 0.5"
    exit 1
fi

INPUT="$1"
OUTPUT="$2"
INTENSITY="${3:-0.05}"
FREQUENCY="${4:-0.3}"

echo "正在为视频 $INPUT 添加 glitch 效果，强度: $INTENSITY，频率: $FREQUENCY..."

# 使用ffmpeg添加 glitch 效果
ffmpeg -i "$INPUT" -filter_complex "[0:v]split=2[main][glitch];[glitch]noise=c0s=0.1:all=1[noisy];[main][noisy]overlay=enable='lt(random(0,1),$FREQUENCY)'[out]" -map "[out]" -map 0:a -c:v libx264 -preset medium -crf 23 -c:a copy "$OUTPUT"

if [ $? -eq 0 ]; then
    echo "glitch 效果添加成功! 输出文件: $OUTPUT"
else
    echo "glitch 效果添加失败!"
    exit 1
fi