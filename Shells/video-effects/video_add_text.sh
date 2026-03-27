#!/bin/bash

# 视频添加文字脚本
# 用法: ./video_add_text.sh input_file output_file text [position] [font_size] [font_color] [duration]

if [ $# -lt 3 ]; then
    echo "用法: ./video_add_text.sh input_file output_file text [position] [font_size] [font_color] [duration]"
    echo "示例: ./video_add_text.sh input.mp4 output.mp4 'Hello World'"
    echo "示例: ./video_add_text.sh input.mp4 output.mp4 'Hello World' bottom-center 36 white"
    exit 1
fi

INPUT="$1"
OUTPUT="$2"
TEXT="$3"
POSITION="${4:-bottom-center}"
FONT_SIZE="${5:-36}"
FONT_COLOR="${6:-white}"
DURATION="${7:-0}"

echo "正在为 $INPUT 添加文字 '$TEXT'，位置: $POSITION，字体大小: $FONT_SIZE，颜色: $FONT_COLOR..."

# 根据位置计算文字位置
case $POSITION in
    top-left)
        POSITION_FILTER="x=10:y=10"
        ;;
    top-center)
        POSITION_FILTER="x=(w-text_w)/2:y=10"
        ;;
    top-right)
        POSITION_FILTER="x=w-text_w-10:y=10"
        ;;
    middle-left)
        POSITION_FILTER="x=10:y=(h-text_h)/2"
        ;;
    middle-center)
        POSITION_FILTER="x=(w-text_w)/2:y=(h-text_h)/2"
        ;;
    middle-right)
        POSITION_FILTER="x=w-text_w-10:y=(h-text_h)/2"
        ;;
    bottom-left)
        POSITION_FILTER="x=10:y=h-text_h-10"
        ;;
    bottom-center)
        POSITION_FILTER="x=(w-text_w)/2:y=h-text_h-10"
        ;;
    bottom-right)
        POSITION_FILTER="x=w-text_w-10:y=h-text_h-10"
        ;;
    *)
        echo "不支持的位置: $POSITION"
        echo "支持的位置: top-left, top-center, top-right, middle-left, middle-center, middle-right, bottom-left, bottom-center, bottom-right"
        exit 1
        ;;
esac

if [ $DURATION -eq 0 ]; then
    # 整个视频都显示文字
    ffmpeg -i "$INPUT" -vf "drawtext=text='$TEXT':fontcolor=$FONT_COLOR:fontsize=$FONT_SIZE:$POSITION_FILTER" -c:v libx264 -preset medium -crf 23 -c:a aac -b:a 128k "$OUTPUT"
else
    # 只在指定时长内显示文字
    ffmpeg -i "$INPUT" -vf "drawtext=text='$TEXT':fontcolor=$FONT_COLOR:fontsize=$FONT_SIZE:$POSITION_FILTER:enable='between(t,0,$DURATION)'" -c:v libx264 -preset medium -crf 23 -c:a aac -b:a 128k "$OUTPUT"
fi

if [ $? -eq 0 ]; then
    echo "添加文字成功! 输出文件: $OUTPUT"
else
    echo "添加文字失败!"
    exit 1
fi