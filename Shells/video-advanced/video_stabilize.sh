#!/bin/bash

# 视频稳定化脚本
# 用法: ./video_stabilize.sh input_file output_file [smoothing]

if [ $# -lt 2 ]; then
    echo "用法: ./video_stabilize.sh input_file output_file [smoothing]"
    echo "示例: ./video_stabilize.sh input.mp4 output.mp4"
    echo "示例: ./video_stabilize.sh input.mp4 output.mp4 0.5"
    exit 1
fi

INPUT="$1"
OUTPUT="$2"
SMOOTHING="${3:-0.1}"

echo "正在稳定视频 $INPUT，平滑度: $SMOOTHING..."

# 使用ffmpeg进行视频稳定化
ffmpeg -i "$INPUT" -filter_complex "[0:v]vidstabdetect=shakiness=10:accuracy=15:result=transforms.trf[vid];[vid]vidstabtransform=smoothing=$SMOOTHING:input=transforms.trf[stab];[stab]unsharp=5:5:0.8:3:3:0.4" -c:v libx264 -preset medium -crf 23 -c:a aac -b:a 128k "$OUTPUT"

if [ $? -eq 0 ]; then
    echo "视频稳定化成功! 输出文件: $OUTPUT"
    # 清理临时文件
    rm -f transforms.trf
else
    echo "视频稳定化失败!"
    exit 1
fi