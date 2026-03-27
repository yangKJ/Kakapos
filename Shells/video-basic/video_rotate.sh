#!/bin/bash

# 视频旋转脚本
# 用法: ./video_rotate.sh input_file output_file rotation_angle

if [ $# -lt 3 ]; then
    echo "用法: ./video_rotate.sh input_file output_file rotation_angle"
    echo "示例: ./video_rotate.sh input.mp4 output.mp4 90"
    echo "示例: ./video_rotate.sh input.mp4 output.mp4 180"
    echo "示例: ./video_rotate.sh input.mp4 output.mp4 270"
    exit 1
fi

INPUT="$1"
OUTPUT="$2"
ROTATION="$3"

echo "正在旋转视频 $INPUT，旋转角度: $ROTATION 度..."

# 根据旋转角度选择不同的滤镜
case $ROTATION in
    90)
        ROTATE_FILTER="transpose=1"
        ;;
    180)
        ROTATE_FILTER="transpose=2,transpose=2"
        ;;
    270)
        ROTATE_FILTER="transpose=2"
        ;;
    *)
        echo "不支持的旋转角度: $ROTATION"
        echo "支持的角度: 90, 180, 270"
        exit 1
        ;;
esac

# 使用ffmpeg进行旋转
ffmpeg -i "$INPUT" -vf "$ROTATE_FILTER" -c:v libx264 -preset medium -crf 23 -c:a aac -b:a 128k "$OUTPUT"

if [ $? -eq 0 ]; then
    echo "旋转成功! 输出文件: $OUTPUT"
else
    echo "旋转失败!"
    exit 1
fi