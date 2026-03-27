#!/bin/bash

# 视频添加字幕脚本
# 用法: ./video_add_subtitle.sh input_file subtitle_file output_file [subtitle_lang]

if [ $# -lt 3 ]; then
    echo "用法: ./video_add_subtitle.sh input_file subtitle_file output_file [subtitle_lang]"
    echo "示例: ./video_add_subtitle.sh input.mp4 subtitle.srt output.mp4"
    echo "示例: ./video_add_subtitle.sh input.mp4 subtitle.srt output.mp4 zh"
    exit 1
fi

INPUT="$1"
SUBTITLE="$2"
OUTPUT="$3"
SUBTITLE_LANG="${4:-zh}"

echo "正在为 $INPUT 添加字幕 $SUBTITLE，语言: $SUBTITLE_LANG..."

# 使用ffmpeg添加字幕
ffmpeg -i "$INPUT" -i "$SUBTITLE" -c:v copy -c:a copy -c:s mov_text -metadata:s:s:0 language=$SUBTITLE_LANG "$OUTPUT"

if [ $? -eq 0 ]; then
    echo "添加字幕成功! 输出文件: $OUTPUT"
else
    echo "添加字幕失败!"
    exit 1
fi