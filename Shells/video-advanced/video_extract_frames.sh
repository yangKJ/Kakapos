#!/bin/bash

# 视频帧提取脚本
# 用法: ./video_extract_frames.sh input_file output_dir [frame_rate] [prefix]

if [ $# -lt 2 ]; then
    echo "用法: ./video_extract_frames.sh input_file output_dir [frame_rate] [prefix]"
    echo "示例: ./video_extract_frames.sh input.mp4 frames"
    echo "示例: ./video_extract_frames.sh input.mp4 frames 1 frame_"
    exit 1
fi

INPUT="$1"
OUTPUT_DIR="$2"
FRAME_RATE="${3:-1}"
PREFIX="${4:-frame_}"

# 创建输出目录
mkdir -p "$OUTPUT_DIR"

echo "正在从 $INPUT 提取帧，帧率: $FRAME_RATE，输出目录: $OUTPUT_DIR..."

# 使用ffmpeg提取帧
ffmpeg -i "$INPUT" -r "$FRAME_RATE" "$OUTPUT_DIR/${PREFIX}%04d.jpg"

if [ $? -eq 0 ]; then
    echo "帧提取成功! 输出目录: $OUTPUT_DIR"
else
    echo "帧提取失败!"
    exit 1
fi