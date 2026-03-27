#!/bin/bash

# 视频色彩匹配脚本
# 用法: ./video_color_match.sh source_file target_file output_file

if [ $# -lt 3 ]; then
    echo "用法: ./video_color_match.sh source_file target_file output_file"
    echo "示例: ./video_color_match.sh source.mp4 target.mp4 output.mp4"
    exit 1
fi

SOURCE="$1"
TARGET="$2"
OUTPUT="$3"

echo "正在匹配视频色彩，将 $SOURCE 的色彩风格应用到 $TARGET..."

# 使用ffmpeg进行色彩匹配
ffmpeg -i "$SOURCE" -i "$TARGET" -filter_complex "[0:v]histogram=mode=color,format=yuv444p[ref];[1:v]histogram=mode=color,format=yuv444p[main];[main][ref]colorchannelmixer=rr=1:rg=0:rb=0:ra=0:gr=0:gg=1:gb=0:ga=0:br=0:bg=0:bb=1:ba=0[out]" -map "[out]" -map 1:a -c:v libx264 -preset medium -crf 23 -c:a copy "$OUTPUT"

if [ $? -eq 0 ]; then
    echo "色彩匹配成功! 输出文件: $OUTPUT"
else
    echo "色彩匹配失败!"
    exit 1
fi