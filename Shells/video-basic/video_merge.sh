#!/bin/bash

# 视频合并脚本
# 用法: ./video_merge.sh output_file input1 input2 [input3 ...]

if [ $# -lt 3 ]; then
    echo "用法: ./video_merge.sh output_file input1 input2 [input3 ...]"
    echo "示例: ./video_merge.sh output.mp4 input1.mp4 input2.mp4"
    exit 1
fi

OUTPUT="$1"
shift
INPUTS=($@)

# 创建临时文件列表
temp_list=$(mktemp)

for input in "${INPUTS[@]}"; do
    echo "file '$input'" >> "$temp_list"
done

echo "正在合并 ${#INPUTS[@]} 个视频文件..."

# 使用ffmpeg进行合并
ffmpeg -f concat -safe 0 -i "$temp_list" -c copy "$OUTPUT"

# 清理临时文件
rm "$temp_list"

if [ $? -eq 0 ]; then
    echo "合并成功! 输出文件: $OUTPUT"
else
    echo "合并失败!"
    exit 1
fi