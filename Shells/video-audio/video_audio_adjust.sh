#!/bin/bash

# 视频音频调整脚本
# 用法: ./video_audio_adjust.sh input_file output_file [volume] [fade_in] [fade_out]

if [ $# -lt 2 ]; then
    echo "用法: ./video_audio_adjust.sh input_file output_file [volume] [fade_in] [fade_out]"
    echo "示例: ./video_audio_adjust.sh input.mp4 output.mp4"
    echo "示例: ./video_audio_adjust.sh input.mp4 output.mp4 1.5 1 1"
    exit 1
fi

INPUT="$1"
OUTPUT="$2"
VOLUME="${3:-1.0}"
FADE_IN="${4:-0}"
FADE_OUT="${5:-0}"

echo "正在调整视频 $INPUT 的音频，音量: $VOLUME，淡入: $FADE_IN 秒，淡出: $FADE_OUT 秒..."

# 构建音频滤镜链
AUDIO_FILTER="volume=$VOLUME"

if [ $FADE_IN -gt 0 ]; then
    AUDIO_FILTER="$AUDIO_FILTER,afade=t=in:st=0:d=$FADE_IN"
fi

if [ $FADE_OUT -gt 0 ]; then
    # 获取视频总时长
    DURATION=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$INPUT")
    # 计算淡出开始时间
    FADE_OUT_START=$(echo "$DURATION - $FADE_OUT" | bc)
    AUDIO_FILTER="$AUDIO_FILTER,afade=t=out:st=$FADE_OUT_START:d=$FADE_OUT"
fi

# 使用ffmpeg调整音频
ffmpeg -i "$INPUT" -filter_complex "[0:a]$AUDIO_FILTER[a]" -map 0:v -map "[a]" -c:v copy -c:a aac -b:a 128k "$OUTPUT"

if [ $? -eq 0 ]; then
    echo "音频调整成功! 输出文件: $OUTPUT"
else
    echo "音频调整失败!"
    exit 1
fi