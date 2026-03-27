#!/bin/bash

# 视频运动分析脚本
# 用法: ./video_analyze_motion.sh input_file output_file [sensitivity]

if [ $# -lt 2 ]; then
    echo "用法: ./video_analyze_motion.sh input_file output_file [sensitivity]"
    echo "示例: ./video_analyze_motion.sh input.mp4 output.mp4"
    echo "示例: ./video_analyze_motion.sh input.mp4 output.mp4 0.1"
    exit 1
fi

INPUT="$1"
OUTPUT="$2"
SENSITIVITY="${3:-0.05}"

echo "正在分析视频 $INPUT 的运动，敏感度: $SENSITIVITY..."

# 使用ffmpeg进行运动分析和可视化
ffmpeg -i "$INPUT" -filter_complex "[0:v]split=2[main][motion];[motion]blur=2:2,metadata=mode=print:file=motion_data.txt,threshold=1,blackframe=90:32[blur];[main][blur]overlay" -c:v libx264 -preset medium -crf 23 -c:a copy "$OUTPUT"

if [ $? -eq 0 ]; then
    echo "运动分析成功! 输出文件: $OUTPUT"
    echo "运动数据已保存到: motion_data.txt"
else
    echo "运动分析失败!"
    exit 1
fi