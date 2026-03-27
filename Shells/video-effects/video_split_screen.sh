#!/bin/bash

# 视频分屏效果脚本
# 用法: ./video_split_screen.sh input1 input2 output_file [layout]

if [ $# -lt 3 ]; then
    echo "用法: ./video_split_screen.sh input1 input2 output_file [layout]"
    echo "示例: ./video_split_screen.sh input1.mp4 input2.mp4 output.mp4"
    echo "示例: ./video_split_screen.sh input1.mp4 input2.mp4 output.mp4 horizontal"
    exit 1
fi

INPUT1="$1"
INPUT2="$2"
OUTPUT="$3"
LAYOUT="${4:-vertical}"

echo "正在创建分屏效果，布局: $LAYOUT..."

if [ "$LAYOUT" = "horizontal" ]; then
    # 水平分屏
    ffmpeg -i "$INPUT1" -i "$INPUT2" -filter_complex "[0:v]scale=iw/2:ih[left];[1:v]scale=iw/2:ih[right];[left][right]hstack=inputs=2[out]" -map "[out]" -c:v libx264 -preset medium -crf 23 -c:a aac -b:a 128k "$OUTPUT"
elif [ "$LAYOUT" = "vertical" ]; then
    # 垂直分屏
    ffmpeg -i "$INPUT1" -i "$INPUT2" -filter_complex "[0:v]scale=iw:ih/2[top];[1:v]scale=iw:ih/2[bottom];[top][bottom]vstack=inputs=2[out]" -map "[out]" -c:v libx264 -preset medium -crf 23 -c:a aac -b:a 128k "$OUTPUT"
elif [ "$LAYOUT" = "grid" ]; then
    # 2x2 网格
    ffmpeg -i "$INPUT1" -i "$INPUT2" -i "$INPUT1" -i "$INPUT2" -filter_complex "[0:v]scale=iw/2:ih/2[0];[1:v]scale=iw/2:ih/2[1];[2:v]scale=iw/2:ih/2[2];[3:v]scale=iw/2:ih/2[3];[0][1]hstack[top];[2][3]hstack[bottom];[top][bottom]vstack[out]" -map "[out]" -c:v libx264 -preset medium -crf 23 -c:a aac -b:a 128k "$OUTPUT"
else
    echo "不支持的布局: $LAYOUT"
    echo "支持的布局: horizontal, vertical, grid"
    exit 1
fi

if [ $? -eq 0 ]; then
    echo "分屏效果创建成功! 输出文件: $OUTPUT"
else
    echo "分屏效果创建失败!"
    exit 1
fi