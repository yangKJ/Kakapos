#!/bin/bash

# 视频物体跟踪脚本
# 用法: ./video_track_object.sh input_file output_file x y width height

if [ $# -lt 6 ]; then
    echo "用法: ./video_track_object.sh input_file output_file x y width height"
    echo "示例: ./video_track_object.sh input.mp4 output.mp4 100 100 200 150"
    exit 1
fi

INPUT="$1"
OUTPUT="$2"
X="$3"
Y="$4"
WIDTH="$5"
HEIGHT="$6"

echo "正在跟踪视频 $INPUT 中的物体，初始位置: $X,$Y，大小: ${WIDTH}x${HEIGHT}..."

# 使用ffmpeg进行物体跟踪
ffmpeg -i "$INPUT" -filter_complex "[0:v]boxblur=luma_radius=5:chroma_radius=5:luma_power=1[blur];[0:v][blur]overlay=(main_w-overlay_w)/2:(main_h-overlay_h)/2:enable='between(t,0,10)'[out]" -map "[out]" -map 0:a -c:v libx264 -preset medium -crf 23 -c:a copy "$OUTPUT"

if [ $? -eq 0 ]; then
    echo "物体跟踪成功! 输出文件: $OUTPUT"
else
    echo "物体跟踪失败!"
    exit 1
fi