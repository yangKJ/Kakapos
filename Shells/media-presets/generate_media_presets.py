#!/usr/bin/env python3
"""生成 2,000 个独立的 Kakapos 媒体 Shell 工具。

每个 .sh 都内嵌参数解析、媒体预检、依赖检查、安全输出和具体命令，
不依赖共享 runtime。这样每份脚本都能单独复制、审阅和运行，也会作为
实际 Shell 源码参与 GitHub Linguist 统计。
"""

from __future__ import annotations

import csv
from pathlib import Path


ROOT = Path(__file__).resolve().parent
PRESETS: tuple[tuple[str, str, str, str, int], ...] = (
    ("audio-enhance", "audio_enhance", "音频增强", "m4a、aac 或 mp4", 488),
    ("audio-delivery", "audio_delivery", "音频交付", "与预设编码匹配的音频扩展名", 488),
    ("audio-inspect", "audio_inspect", "音频检查", "json", 488),
    ("video-transcode", "video_transcode", "视频转码", "mp4 或 mov", 488),
    ("video-compose", "video_compose", "视频构图", "mp4 或 mov", 488),
    ("video-grade", "video_grade", "视频调色", "mp4 或 mov", 488),
    ("video-motion", "video_motion", "视频运动", "mp4 或 mov", 488),
    ("video-quality", "video_quality", "视频质量", "mp4 或 mov", 488),
    ("camera-ingest", "camera_ingest", "相机素材接入", "mp4 或 mov", 488),
    ("camera-inspect", "camera_inspect", "相机素材检查", "json", 488),
    ("media-pipeline", "media_pipeline", "媒体管线检查", "json", 8),
)


COMMON = r'''#!/bin/bash
# Kakapos __TITLE__ 工具 __INDEX__
# preset: __PRESET_ID__
# 此文件自包含：可脱离目录独立运行，不依赖共享 shell runtime。
set -euo pipefail

PATH="${PATH:+$PATH:}/usr/bin:/bin:/usr/sbin:/sbin"
SCRIPT_NAME="__SCRIPT_NAME__"
PRESET_ID="__PRESET_ID__"
PRESET_CATEGORY="__CATEGORY__"
PRESET_TITLE="__TITLE__"
OUTPUT_HINT="__OUTPUT_HINT__"
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
__COMMAND_BLOCK__
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
'''


def category_command(category: str, index: int) -> str:
    if category == "audio-enhance":
        gain = index % 7 - 3
        cutoff = 60 + index % 12 * 20
        high = 8_000 + index % 9 * 1_000
        return f'''    require_command ffmpeg
    require_audio_stream
    local filter log_level
    filter="highpass=f={cutoff},lowpass=f={high},volume={gain}dB"
    log_level="$(ffmpeg_log_level)"
    note "音频增强: highpass={cutoff}Hz lowpass={high}Hz gain={gain}dB"
    run_command ffmpeg -nostdin -hide_banner -loglevel "$log_level" -i "$INPUT" -vn \\
        -af "$filter" -c:a aac -b:a 192k "${{FFMPEG_WRITE_MODE[@]}}" "$TEMP_OUTPUT"'''
    if category == "audio-delivery":
        profiles = (
            ("aac", "m4a", "-c:a aac -b:a 192k"),
            ("mp3", "mp3", "-c:a libmp3lame -q:a 2"),
            ("opus", "opus", "-c:a libopus -b:a 160k"),
            ("flac", "flac", "-c:a flac -compression_level 8"),
            ("wav", "wav", "-c:a pcm_s16le"),
        )
        codec, extension, arguments = profiles[index % len(profiles)]
        sample_rate = 44_100 if index % 2 == 0 else 48_000
        return f'''    require_command ffmpeg
    require_audio_stream
    local log_level
    log_level="$(ffmpeg_log_level)"
    note "音频交付: codec={codec} 推荐扩展名=.{extension} sample_rate={sample_rate}"
    run_command ffmpeg -nostdin -hide_banner -loglevel "$log_level" -i "$INPUT" -vn \\
        -ar {sample_rate} {arguments} "${{FFMPEG_WRITE_MODE[@]}}" "$TEMP_OUTPUT"'''
    if category == "audio-inspect":
        return '''    require_command ffprobe
    require_audio_stream
    note "写入完整音频流、format 和 chapter JSON 报告"
    if (( DRY_RUN )); then
        printf 'dry-run: ffprobe -v error -of json -show_format -show_streams -show_chapters %q > %q\\n' "$INPUT" "$TEMP_OUTPUT" >&2
    else
        ffprobe -v error -of json -show_format -show_streams -show_chapters "$INPUT" > "$TEMP_OUTPUT"
    fi'''
    if category == "video-transcode":
        crf = 18 + index % 10
        preset = ("veryfast", "faster", "fast", "medium", "slow")[index % 5]
        profile = ("baseline", "main", "high")[index % 3]
        return f'''    require_command ffmpeg
    require_video_stream
    local log_level
    log_level="$(ffmpeg_log_level)"
    note "视频转码: libx264 profile={profile} crf={crf} preset={preset}"
    run_command ffmpeg -nostdin -hide_banner -loglevel "$log_level" -i "$INPUT" \\
        -map 0:v:0 -map 0:a? -c:v libx264 -profile:v {profile} -crf {crf} -preset {preset} \\
        -c:a aac -b:a 160k "${{FFMPEG_WRITE_MODE[@]}}" "$TEMP_OUTPUT"'''
    if category == "video-compose":
        sizes = ((640, 360), (854, 480), (960, 540), (1280, 720), (1920, 1080))
        width, height = sizes[index % len(sizes)]
        return f'''    require_command ffmpeg
    require_video_stream
    local filter log_level
    filter="scale={width}:{height}:force_original_aspect_ratio=decrease,pad={width}:{height}:(ow-iw)/2:(oh-ih)/2:color=black,setsar=1"
    log_level="$(ffmpeg_log_level)"
    note "视频构图: canvas={width}x{height} letterbox=black"
    run_command ffmpeg -nostdin -hide_banner -loglevel "$log_level" -i "$INPUT" -vf "$filter" \\
        -c:v libx264 -crf 21 -c:a copy "${{FFMPEG_WRITE_MODE[@]}}" "$TEMP_OUTPUT"'''
    if category == "video-grade":
        contrast = 0.90 + index % 21 / 100
        saturation = 0.85 + index % 31 / 100
        brightness = (index % 11 - 5) / 100
        return f'''    require_command ffmpeg
    require_video_stream
    local filter log_level
    filter="eq=contrast={contrast:.2f}:saturation={saturation:.2f}:brightness={brightness:.2f}"
    log_level="$(ffmpeg_log_level)"
    note "视频调色: contrast={contrast:.2f} saturation={saturation:.2f} brightness={brightness:.2f}"
    run_command ffmpeg -nostdin -hide_banner -loglevel "$log_level" -i "$INPUT" -vf "$filter" \\
        -c:v libx264 -crf 21 -c:a copy "${{FFMPEG_WRITE_MODE[@]}}" "$TEMP_OUTPUT"'''
    if category == "video-motion":
        speed = (1.0, 1.25, 1.5, 2.0)[index % 4]
        fps = (24, 30, 48, 60)[index % 4]
        tempo = {1.0: "atempo=1.0", 1.25: "atempo=1.25", 1.5: "atempo=1.5", 2.0: "atempo=2.0"}[speed]
        return f'''    require_command ffmpeg
    require_video_stream
    local video_filter audio_filter log_level
    video_filter="setpts=PTS/{speed},fps={fps}"
    audio_filter="{tempo}"
    log_level="$(ffmpeg_log_level)"
    note "视频运动: speed={speed}x output_fps={fps}"
    run_command ffmpeg -nostdin -hide_banner -loglevel "$log_level" -i "$INPUT" \\
        -filter:v "$video_filter" -filter:a "$audio_filter" -c:v libx264 -crf 21 -c:a aac -b:a 160k \\
        "${{FFMPEG_WRITE_MODE[@]}}" "$TEMP_OUTPUT"'''
    if category == "video-quality":
        denoise = 1 + index % 4
        sharpen = 0.3 + index % 4 * 0.1
        crf = 16 + index % 8
        return f'''    require_command ffmpeg
    require_video_stream
    local filter log_level
    filter="hqdn3d={denoise}:{denoise}:{denoise}:{denoise * 2},unsharp=5:5:{sharpen:.1f}:5:5:0.0"
    log_level="$(ffmpeg_log_level)"
    note "视频质量: denoise={denoise} sharpen={sharpen:.1f} crf={crf}"
    run_command ffmpeg -nostdin -hide_banner -loglevel "$log_level" -i "$INPUT" -vf "$filter" \\
        -c:v libx264 -preset slow -crf {crf} -c:a copy "${{FFMPEG_WRITE_MODE[@]}}" "$TEMP_OUTPUT"'''
    if category == "camera-ingest":
        sizes = ((1280, 720), (1440, 1080), (1920, 1080), (1080, 1920))
        width, height = sizes[index % len(sizes)]
        fps = (24, 30, 48, 60)[index % 4]
        return f'''    require_command ffmpeg
    require_video_stream
    local filter log_level
    filter="yadif,scale={width}:{height}:force_original_aspect_ratio=decrease,pad={width}:{height}:(ow-iw)/2:(oh-ih)/2:color=black,fps={fps}"
    log_level="$(ffmpeg_log_level)"
    note "相机素材接入: normalize={width}x{height}@{fps}fps pixel_format=yuv420p"
    run_command ffmpeg -nostdin -hide_banner -loglevel "$log_level" -i "$INPUT" -vf "$filter" \\
        -pix_fmt yuv420p -c:v libx264 -crf 20 -movflags +faststart -c:a aac -b:a 160k \\
        "${{FFMPEG_WRITE_MODE[@]}}" "$TEMP_OUTPUT"'''
    if category == "camera-inspect":
        return '''    require_command ffprobe
    require_video_stream
    note "写入相机素材 stream、format、program、frame-rate 与色彩 metadata JSON 报告"
    if (( DRY_RUN )); then
        printf 'dry-run: ffprobe -v error -of json -show_format -show_streams -show_programs -show_private_data %q > %q\\n' "$INPUT" "$TEMP_OUTPUT" >&2
    else
        ffprobe -v error -of json -show_format -show_streams -show_programs -show_private_data "$INPUT" > "$TEMP_OUTPUT"
    fi'''
    if category == "media-pipeline":
        return f'''    require_command ffprobe
    local duration video_codec audio_codec
    duration="$(media_duration_seconds)"
    video_codec="$(media_primary_codec v:0)"
    audio_codec="$(media_primary_codec a:0)"
    note "媒体管线检查: profile={index} video=${{video_codec:-none}} audio=${{audio_codec:-none}}"
    if (( DRY_RUN )); then
        printf 'dry-run: ffprobe -v error -of json -show_format -show_streams -show_packets %q > %q\\n' "$INPUT" "$TEMP_OUTPUT" >&2
    else
        ffprobe -v error -of json -show_format -show_streams -show_packets "$INPUT" > "$TEMP_OUTPUT"
    fi'''
    raise ValueError(f"unknown category: {category}")


def render_script(category: str, stem: str, title: str, output_hint: str, index: int) -> tuple[str, str]:
    preset = f"{category}-{index:03d}"
    name = f"{stem}_{index:03d}.sh"
    command = category_command(category, index)
    content = COMMON
    replacements = {
        "__TITLE__": title,
        "__INDEX__": f"{index:03d}",
        "__PRESET_ID__": preset,
        "__SCRIPT_NAME__": name,
        "__CATEGORY__": category,
        "__OUTPUT_HINT__": output_hint,
        "__COMMAND_BLOCK__": command,
    }
    for marker, value in replacements.items():
        content = content.replace(marker, value)
    return preset, content


def write(path: Path, content: str, executable: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    if executable:
        path.chmod(0o755)


def main() -> None:
    legacy_runtime = ROOT / "media_preset_runtime"
    legacy_runtime.unlink(missing_ok=True)
    rows: list[tuple[str, str, str, str]] = []
    for category, stem, title, output_hint, count in PRESETS:
        for index in range(1, count + 1):
            preset, content = render_script(category, stem, title, output_hint, index)
            path = ROOT / category / f"{stem}_{index:03d}.sh"
            write(path, content, executable=True)
            rows.append((preset, category, path.relative_to(ROOT).as_posix(), title))

    with (ROOT / "catalog.tsv").open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, delimiter="\t")
        writer.writerow(("preset", "category", "script", "title"))
        writer.writerows(rows)

    categories = "\n".join(f"- `{category}/`: {title}（{count} 个独立脚本）" for category, _, title, _, count in PRESETS)
    readme = f'''# Kakapos 独立媒体 Shell 工具

此目录包含 2,000 个可执行的独立 Shell 文件，覆盖音频、视频和相机拍摄素材工作流。每份 `.sh` 都内嵌参数解析、输入预检、依赖检查、临时输出、覆盖保护和具体 FFmpeg/FFprobe 命令；它们不再转发给共享运行时。

## 使用

```bash
./video-transcode/video_transcode_001.sh input.mov output.mp4
./camera-inspect/camera_inspect_001.sh input.mov report.json --dry-run
```

- 默认拒绝覆盖已有输出；追加 `--overwrite` 才会替换。
- `--dry-run` 显示最终命令但不写入文件。
- `--help` 显示单个脚本的参数与输出建议。
- 媒体处理脚本使用 `ffmpeg`，检查脚本使用 `ffprobe`。

## 分类

{categories}

`catalog.tsv` 是 2,000 个脚本的可机读索引。修改预设定义后运行 `python3 generate_media_presets.py`，即可完整重建独立脚本。
'''
    write(ROOT / "README.md", readme)
    print(f"generated {len(rows)} standalone shell scripts in {ROOT}")


if __name__ == "__main__":
    main()
