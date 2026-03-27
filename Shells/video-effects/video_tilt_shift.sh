#!/bin/bash

# 视频移轴效果脚本
# 用法: ./video_tilt_shift.sh input_file output_file [focus_area] [blur_strength]

if [ $# -lt 2 ]; then
    echo "用法: ./video_tilt_shift.sh input_file output_file [focus_area] [blur_strength]"
    echo "示例: ./video_tilt_shift.sh input.mp4 output.mp4"
    echo "示例: ./video_tilt_shift.sh input.mp4 output.mp4 0.5 10"
    exit 1
fi

INPUT="$1"
OUTPUT="$2"
FOCUS_AREA="${3:-0.5}"
BLUR_STRENGTH="${4:-5}"

echo "正在为视频 $INPUT 添加移轴效果，聚焦区域: $FOCUS_AREA，模糊强度: $BLUR_STRENGTH..."

# 使用ffmpeg添加移轴效果
ffmpeg -i "$INPUT" -filter_complex "[0:v]boxblur=w=$BLUR_STRENGTH:h=$BLUR_STRENGTH:box=1[blur];[0:v][blur]overlay=0:0:enable='between(y,ih*$FOCUS_AREA-ih/6,ih*$FOCUS_AREA+ih/6)'" -c:v libx264 -preset medium -crf 23 -c:a copy "$OUTPUT"

if [ $? -eq 0 ]; then
    echo "移轴效果添加成功! 输出文件: $OUTPUT"
else
    echo "移轴效果添加失败!"
    exit 1
fi