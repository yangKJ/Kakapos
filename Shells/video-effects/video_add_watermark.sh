#!/bin/bash

# 视频添加水印脚本
# 用法: ./video_add_watermark.sh input_file watermark_file output_file [position] [opacity]

if [ $# -lt 3 ]; then
    echo "用法: ./video_add_watermark.sh input_file watermark_file output_file [position] [opacity]"
    echo "示例: ./video_add_watermark.sh input.mp4 watermark.png output.mp4"
    echo "示例: ./video_add_watermark.sh input.mp4 watermark.png output.mp4 bottom-right 0.5"
    exit 1
fi

INPUT="$1"
WATERMARK="$2"
OUTPUT="$3"
POSITION="${4:-bottom-right}"
OPACITY="${5:-0.3}"

echo "正在为 $INPUT 添加水印，位置: $POSITION，透明度: $OPACITY..."

# 根据位置计算水印位置
case $POSITION in
    top-left)
        POSITION_FILTER="overlay=10:10"
        ;;
    top-right)
        POSITION_FILTER="overlay=main_w-overlay_w-10:10"
        ;;
    bottom-left)
        POSITION_FILTER="overlay=10:main_h-overlay_h-10"
        ;;
    bottom-right)
        POSITION_FILTER="overlay=main_w-overlay_w-10:main_h-overlay_h-10"
        ;;
    center)
        POSITION_FILTER="overlay=(main_w-overlay_w)/2:(main_h-overlay_h)/2"
        ;;
    *)
        echo "不支持的位置: $POSITION"
        echo "支持的位置: top-left, top-right, bottom-left, bottom-right, center"
        exit 1
        ;;
esac

# 使用ffmpeg添加水印
ffmpeg -i "$INPUT" -i "$WATERMARK" -filter_complex "[1:v]format=rgba,colorchannelmixer=aa=${OPACITY}[watermark];[0:v][watermark]${POSITION_FILTER}" -c:v libx264 -preset medium -crf 23 -c:a aac -b:a 128k "$OUTPUT"

if [ $? -eq 0 ]; then
    echo "添加水印成功! 输出文件: $OUTPUT"
else
    echo "添加水印失败!"
    exit 1
fi