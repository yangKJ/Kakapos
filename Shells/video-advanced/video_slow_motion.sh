#!/bin/bash

# 视频慢动作脚本
# 用法: ./video_slow_motion.sh input_file output_file [slow_factor] [start_time] [duration]

if [ $# -lt 2 ]; then
    echo "用法: ./video_slow_motion.sh input_file output_file [slow_factor] [start_time] [duration]"
    echo "示例: ./video_slow_motion.sh input.mp4 output.mp4"
    echo "示例: ./video_slow_motion.sh input.mp4 output.mp4 0.5 10 5"
    exit 1
fi

INPUT="$1"
OUTPUT="$2"
SLOW_FACTOR="${3:-0.5}"
START_TIME="${4:-0}"
DURATION="${5:-0}"

echo "正在为视频 $INPUT 创建慢动作效果，慢动作因子: $SLOW_FACTOR..."

if [ $DURATION -eq 0 ]; then
    # 整个视频都应用慢动作
    ffmpeg -i "$INPUT" -filter_complex "[0:v]setpts=1/${SLOW_FACTOR}*PTS[v];[0:a]atempo=${SLOW_FACTOR}[a]" -map "[v]" -map "[a]" -c:v libx264 -preset medium -crf 23 -c:a aac -b:a 128k "$OUTPUT"
else
    # 只在指定时间段应用慢动作
    ffmpeg -i "$INPUT" -filter_complex "[0:v]trim=0:$START_TIME,setpts=PTS-STARTPTS[begin];[0:v]trim=$START_TIME:$START_TIME+$DURATION,setpts=1/${SLOW_FACTOR}*PTS-STARTPTS[slow];[0:v]trim=$START_TIME+$DURATION,setpts=PTS-STARTPTS[end];[begin][slow][end]concat=n=3:v=1:a=0[v];[0:a]atrim=0:$START_TIME,asetpts=PTS-STARTPTS[abegin];[0:a]atrim=$START_TIME:$START_TIME+$DURATION,atempo=${SLOW_FACTOR},asetpts=PTS-STARTPTS[aslow];[0:a]atrim=$START_TIME+$DURATION,asetpts=PTS-STARTPTS[aend];[abegin][aslow][aend]concat=n=3:v=0:a=1[a]" -map "[v]" -map "[a]" -c:v libx264 -preset medium -crf 23 -c:a aac -b:a 128k "$OUTPUT"
fi

if [ $? -eq 0 ]; then
    echo "慢动作效果创建成功! 输出文件: $OUTPUT"
else
    echo "慢动作效果创建失败!"
    exit 1
fi