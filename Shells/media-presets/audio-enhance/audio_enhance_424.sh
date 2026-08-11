#!/bin/bash
# Kakapos 音频增强 工具 424
# preset: audio-enhance-424
# 此文件自包含：可脱离目录独立运行，不依赖共享 shell runtime。
set -euo pipefail

PATH="${PATH:+$PATH:}/usr/bin:/bin:/usr/sbin:/sbin"
SCRIPT_NAME="audio_enhance_424.sh"
PRESET_ID="audio-enhance-424"
PRESET_CATEGORY="audio-enhance"
PRESET_TITLE="音频增强"
OUTPUT_HINT="m4a、aac 或 mp4"
INPUT=""
OUTPUT=""
OVERWRITE=0
DRY_RUN=0
QUIET=0
TEMP_OUTPUT=""
FFMPEG_WRITE_MODE=(-n)

usage() {
    cat <<USAGE
Kakapos ${PRESET_TITLE} preset ${PRESET_ID}

用法: ./${SCRIPT_NAME} input_file output_file [--overwrite] [--dry-run] [--quiet]
  input_file   需要处理或检查的音视频、相机拍摄素材
  output_file  输出媒体或报告；建议扩展名：${OUTPUT_HINT}
  --overwrite  明确允许替换已存在的输出文件
  --dry-run    只输出即将执行的命令，不写入文件
  --quiet      降低 FFmpeg 的日志输出
USAGE
}

die() {
    printf '%s\n' "错误: $*" >&2
    exit 1
}

note() {
    if (( ! QUIET )); then
        printf '%s\n' "[$PRESET_ID] $*" >&2
    fi
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "缺少依赖命令: $1"
}

is_help_option() {
    [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]
}

reject_option_like_path() {
    [[ "$1" != -* ]] || die "文件路径不能以连字符开头: $1"
}

require_regular_input() {
    [[ -f "$INPUT" ]] || die "输入文件不存在: $INPUT"
    [[ -s "$INPUT" ]] || die "输入文件为空: $INPUT"
}

stream_type() {
    ffprobe -v error -select_streams "$1" -show_entries stream=codec_type \
        -of default=noprint_wrappers=1:nokey=1 "$INPUT" 2>/dev/null | head -n 1
}

require_audio_stream() {
    require_command ffprobe
    [[ "$(stream_type a:0)" == "audio" ]] || die "输入素材不含可用音频流"
}

require_video_stream() {
    require_command ffprobe
    [[ "$(stream_type v:0)" == "video" ]] || die "输入素材不含可用视频流"
}

media_duration_seconds() {
    require_command ffprobe
    ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 \
        "$INPUT" 2>/dev/null || true
}

media_primary_codec() {
    local selector="$1"
    require_command ffprobe
    ffprobe -v error -select_streams "$selector" -show_entries stream=codec_name \
        -of default=noprint_wrappers=1:nokey=1 "$INPUT" 2>/dev/null | head -n 1 || true
}

print_media_summary() {
    local duration video_codec audio_codec
    duration="$(media_duration_seconds)"
    video_codec="$(media_primary_codec v:0)"
    audio_codec="$(media_primary_codec a:0)"
    note "输入: duration=${duration:-unknown}s video=${video_codec:-none} audio=${audio_codec:-none}"
}

parse_arguments() {
    local positional=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --overwrite) OVERWRITE=1 ;;
            --dry-run) DRY_RUN=1 ;;
            --quiet) QUIET=1 ;;
            --help|-h) usage; exit 0 ;;
            --) shift; positional+=("$@"); break ;;
            -*) die "不支持的选项: $1" ;;
            *) positional+=("$1") ;;
        esac
        shift
    done
    [[ ${#positional[@]} -eq 2 ]] || { usage >&2; exit 64; }
    INPUT="${positional[0]}"
    OUTPUT="${positional[1]}"
}

prepare_output() {
    local output_dir output_name output_extension
    reject_option_like_path "$INPUT"
    reject_option_like_path "$OUTPUT"
    [[ "$INPUT" != "$OUTPUT" ]] || die "输入和输出不能是同一文件"
    output_dir="$(dirname "$OUTPUT")"
    output_name="$(basename "$OUTPUT")"
    output_extension="${output_name##*.}"
    [[ "$output_name" != "$output_extension" ]] || die "输出文件需要扩展名"
    if [[ -e "$OUTPUT" && $OVERWRITE -ne 1 ]]; then
        die "输出已存在；如确认覆盖，请附加 --overwrite: $OUTPUT"
    fi
    if (( ! DRY_RUN )); then
        mkdir -p "$output_dir"
    fi
    TEMP_OUTPUT="$output_dir/.${output_name}.kakapos-${RANDOM}.${output_extension}"
    if (( OVERWRITE )); then
        FFMPEG_WRITE_MODE=(-y)
    fi
}

cleanup() {
    [[ -n "$TEMP_OUTPUT" ]] && rm -f "$TEMP_OUTPUT"
}

commit_output() {
    if (( ! DRY_RUN )); then
        [[ -s "$TEMP_OUTPUT" ]] || die "未生成有效临时输出"
        mv -f "$TEMP_OUTPUT" "$OUTPUT"
        note "已写入: $OUTPUT"
    fi
}

run_command() {
    if (( DRY_RUN )); then
        printf 'dry-run:' >&2
        printf ' %q' "$@" >&2
        printf '\n' >&2
    else
        "$@"
    fi
}

ffmpeg_log_level() {
    if (( QUIET )); then
        printf '%s' error
    else
        printf '%s' warning
    fi
}

validate_output_parent() {
    local parent
    parent="$(dirname "$OUTPUT")"
    [[ -d "$parent" || $DRY_RUN -eq 0 ]] || die "输出目录不存在: $parent"
}

describe_preset() {
    note "类别=${PRESET_CATEGORY} 输出建议=${OUTPUT_HINT} dry_run=${DRY_RUN} overwrite=${OVERWRITE}"
}

execute_preset() {
    require_command ffmpeg
    require_audio_stream
    local filter log_level
    filter="highpass=f=140,lowpass=f=9000,volume=1dB"
    log_level="$(ffmpeg_log_level)"
    note "音频增强: highpass=140Hz lowpass=9000Hz gain=1dB"
    run_command ffmpeg -nostdin -hide_banner -loglevel "$log_level" -i "$INPUT" -vn \
        -af "$filter" -c:a aac -b:a 192k "${FFMPEG_WRITE_MODE[@]}" "$TEMP_OUTPUT"
}

main() {
    if is_help_option "${1:-}"; then
        usage
        exit 0
    fi
    parse_arguments "$@"
    require_regular_input
    prepare_output
    trap cleanup EXIT HUP INT TERM
    validate_output_parent
    describe_preset
    print_media_summary
    execute_preset
    commit_output
}

main "$@"
