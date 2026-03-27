#!/bin/bash

# 视频降噪脚本
# 用法: ./video_denoise.sh input_file output_file [strength]

if [ $# -lt 2 ]; then
    echo "用法: ./video_denoise.sh input_file output_file [strength]"
    echo "示例: ./video_denoise.sh input.mp4 output.mp4"
    echo "示例: ./video_denoise.sh input.mp4 output.mp4 0.5"
    exit 1
fi

INPUT="$1"
OUTPUT="$2"
STRENGTH="${3:-0.3}"

echo "正在为视频 $INPUT 降噪，强度: $STRENGTH..."

# 使用ffmpeg进行视频降噪
ffmpeg -i "$INPUT" -filter_complex "[0:v]nlmeans=s=$STRENGTH:t=1.0:h=2" -c:v libx264 -preset medium -crf 23 -c:a copy "$OUTPUT"

if [ $? -eq 0 ]; then
    echo "降噪成功! 输出文件: $OUTPUT"
else
    echo "降噪失败!"
    exit 1
fi