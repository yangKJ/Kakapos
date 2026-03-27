#!/bin/bash

# 视频速度调整脚本
# 用法: ./video_speed.sh input_file output_file speed_factor

if [ $# -lt 3 ]; then
    echo "用法: ./video_speed.sh input_file output_file speed_factor"
    echo "示例: ./video_speed.sh input.mp4 output.mp4 2"
    echo "示例: ./video_speed.sh input.mp4 output.mp4 0.5"
    exit 1
fi

INPUT="$1"
OUTPUT="$2"
SPEED="$3"

echo "正在调整视频 $INPUT 的速度，速度因子: $SPEED..."

# 计算音频速度因子
AUDIO_SPEED=$(echo "scale=2; 1 / $SPEED" | bc)

# 使用ffmpeg调整视频速度
ffmpeg -i "$INPUT" -filter_complex "[0:v]setpts=$AUDIO_SPEED*PTS[v];[0:a]atempo=$SPEED[a]" -map "[v]" -map "[a]" -c:v libx264 -preset medium -crf 23 -c:a aac -b:a 128k "$OUTPUT"

if [ $? -eq 0 ]; then
    echo "速度调整成功! 输出文件: $OUTPUT"
else
    echo "速度调整失败!"
    exit 1
fi