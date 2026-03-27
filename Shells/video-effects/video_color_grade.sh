#!/bin/bash

# 视频色彩分级脚本
# 用法: ./video_color_grade.sh input_file output_file [brightness] [contrast] [saturation] [hue] [gamma]

if [ $# -lt 2 ]; then
    echo "用法: ./video_color_grade.sh input_file output_file [brightness] [contrast] [saturation] [hue] [gamma]"
    echo "示例: ./video_color_grade.sh input.mp4 output.mp4"
    echo "示例: ./video_color_grade.sh input.mp4 output.mp4 0 1.2 1.1 0 1.0"
    exit 1
fi

INPUT="$1"
OUTPUT="$2"
BRIGHTNESS="${3:-0}"
CONTRAST="${4:-1.0}"
SATURATION="${5:-1.0}"
HUE="${6:-0}"
GAMMA="${7:-1.0}"

echo "正在为视频 $INPUT 进行色彩分级..."
echo "亮度: $BRIGHTNESS, 对比度: $CONTRAST, 饱和度: $SATURATION, 色调: $HUE, 伽马: $GAMMA"

# 使用ffmpeg进行色彩分级
ffmpeg -i "$INPUT" -filter_complex "[0:v]eq=brightness=$BRIGHTNESS:contrast=$CONTRAST:saturation=$SATURATION:hue=$HUE:gamma=$GAMMA" -c:v libx264 -preset medium -crf 23 -c:a copy "$OUTPUT"

if [ $? -eq 0 ]; then
    echo "色彩分级成功! 输出文件: $OUTPUT"
else
    echo "色彩分级失败!"
    exit 1
fi