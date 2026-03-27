#!/bin/bash

# 视频批量处理脚本
# 用法: ./video_batch_process.sh input_dir output_dir command [command_args...]

if [ $# -lt 3 ]; then
    echo "用法: ./video_batch_process.sh input_dir output_dir command [command_args...]"
    echo "示例: ./video_batch_process.sh input_videos output_videos compress"
    echo "示例: ./video_batch_process.sh input_videos output_videos convert mp4"
    exit 1
fi

INPUT_DIR="$1"
OUTPUT_DIR="$2"
COMMAND="$3"
shift 3
COMMAND_ARGS="$@"

# 创建输出目录
mkdir -p "$OUTPUT_DIR"

echo "正在批量处理目录 $INPUT_DIR 中的视频，命令: $COMMAND..."

# 遍历输入目录中的视频文件
for file in "$INPUT_DIR"/*.{mp4,mov,avi,mkv,wmv,flv}; do
    if [ -f "$file" ]; then
        # 获取文件名（不含路径）
        filename=$(basename "$file")
        # 获取文件名（不含扩展名）
        filename_no_ext=$(echo "$filename" | cut -d. -f1)
        # 构建输出文件路径
        output_file="$OUTPUT_DIR/$filename"
        
        echo "处理文件: $filename"
        
        # 根据命令执行不同的处理
        case $COMMAND in
            compress)
                ./video_compress.sh "$file" "$output_file" $COMMAND_ARGS
                ;;
            convert)
                output_file="$OUTPUT_DIR/${filename_no_ext}.$COMMAND_ARGS"
                ./video_convert.sh "$file" "$output_file"
                ;;
            trim)
                ./video_trim.sh "$file" "$output_file" $COMMAND_ARGS
                ;;
            rotate)
                ./video_rotate.sh "$file" "$output_file" $COMMAND_ARGS
                ;;
            add_watermark)
                watermark_file="$COMMAND_ARGS"
                ./video_add_watermark.sh "$file" "$watermark_file" "$output_file"
                ;;
            *)
                echo "不支持的命令: $COMMAND"
                echo "支持的命令: compress, convert, trim, rotate, add_watermark"
                exit 1
                ;;
        esac
    fi
done

echo "批量处理完成!"
