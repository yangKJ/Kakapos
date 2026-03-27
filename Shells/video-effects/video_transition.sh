#!/bin/bash

# 视频转场效果脚本
# 用法: ./video_transition.sh input1 input2 output transition_type [transition_duration]

if [ $# -lt 4 ]; then
    echo "用法: ./video_transition.sh input1 input2 output transition_type [transition_duration]"
    echo "示例: ./video_transition.sh input1.mp4 input2.mp4 output.mp4 fade"
    echo "示例: ./video_transition.sh input1.mp4 input2.mp4 output.mp4 slide 1"
    exit 1
fi

INPUT1="$1"
INPUT2="$2"
OUTPUT="$3"
TRANSITION="$4"
DURATION="${5:-0.5}"

echo "正在为视频添加转场效果，转场类型: $TRANSITION，时长: $DURATION 秒..."

# 根据转场类型选择不同的滤镜
case $TRANSITION in
    fade)
        TRANSITION_FILTER="xfade=transition=fade:duration=$DURATION:offset='duration(0)-$DURATION'"
        ;;
    slide)
        TRANSITION_FILTER="xfade=transition=slideleft:duration=$DURATION:offset='duration(0)-$DURATION'"
        ;;
    zoom)
        TRANSITION_FILTER="xfade=transition=zoom:duration=$DURATION:offset='duration(0)-$DURATION'"
        ;;
    dissolve)
        TRANSITION_FILTER="xfade=transition=dissolve:duration=$DURATION:offset='duration(0)-$DURATION'"
        ;;
    *)
        echo "不支持的转场类型: $TRANSITION"
        echo "支持的转场类型: fade, slide, zoom, dissolve"
        exit 1
        ;;
esac

# 使用ffmpeg添加转场效果
ffmpeg -i "$INPUT1" -i "$INPUT2" -filter_complex "$TRANSITION_FILTER" -c:v libx264 -preset medium -crf 23 -c:a aac -b:a 128k "$OUTPUT"

if [ $? -eq 0 ]; then
    echo "添加转场效果成功! 输出文件: $OUTPUT"
else
    echo "添加转场效果失败!"
    exit 1
fi