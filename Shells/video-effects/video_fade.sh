#!/bin/bash

# 视频淡入淡出效果脚本
# 用法: ./video_fade.sh input_file output_file [fade_in_duration] [fade_out_duration]

if [ $# -lt 2 ]; then
    echo "用法: ./video_fade.sh input_file output_file [fade_in_duration] [fade_out_duration]"
    echo "示例: ./video_fade.sh input.mp4 output.mp4"
    echo "示例: ./video_fade.sh input.mp4 output.mp4 2 3"
    exit 1
fi

INPUT="$1"
OUTPUT="$2"
FADE_IN="${3:-1}"
FADE_OUT="${4:-1}"

echo "正在为视频 $INPUT 添加淡入淡出效果，淡入时长: $FADE_IN 秒，淡出时长: $FADE_OUT 秒..."

# 获取视频总时长
DURATION=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$INPUT")

# 计算淡出开始时间
FADE_OUT_START=$(echo "$DURATION - $FADE_OUT" | bc)

# 使用ffmpeg添加淡入淡出效果
ffmpeg -i "$INPUT" -filter_complex "[0:v]fade=t=in:st=0:d=$FADE_IN,fade=t=out:st=$FADE_OUT_START:d=$FADE_OUT[out]" -map "[out]" -map 0:a -c:v libx264 -preset medium -crf 23 -c:a copy "$OUTPUT"

if [ $? -eq 0 ]; then
    echo "淡入淡出效果添加成功! 输出文件: $OUTPUT"
else
    echo "淡入淡出效果添加失败!"
    exit 1
fi