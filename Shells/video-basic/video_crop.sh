#!/bin/bash

# 视频裁剪脚本
# 用法: ./video_crop.sh input_file output_file width height x y

if [ $# -lt 6 ]; then
    echo "用法: ./video_crop.sh input_file output_file width height x y"
    echo "示例: ./video_crop.sh input.mp4 output.mp4 1280 720 0 0"
    echo "示例: ./video_crop.sh input.mp4 output.mp4 1000 600 100 50"
    exit 1
fi

INPUT="$1"
OUTPUT="$2"
WIDTH="$3"
HEIGHT="$4"
X="$5"
Y="$6"

echo "正在裁剪视频 $INPUT，裁剪区域: ${WIDTH}x${HEIGHT}，起始位置: $X,$Y..."

# 使用ffmpeg进行裁剪
ffmpeg -i "$INPUT" -vf "crop=$WIDTH:$HEIGHT:$X:$Y" -c:v libx264 -preset medium -crf 23 -c:a aac -b:a 128k "$OUTPUT"

if [ $? -eq 0 ]; then
    echo "裁剪成功! 输出文件: $OUTPUT"
else
    echo "裁剪失败!"
    exit 1
fi