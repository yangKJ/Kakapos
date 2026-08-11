# Kakapos 独立媒体 Shell 工具

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

- `audio-enhance/`: 音频增强（488 个独立脚本）
- `audio-delivery/`: 音频交付（488 个独立脚本）
- `audio-inspect/`: 音频检查（488 个独立脚本）
- `video-transcode/`: 视频转码（488 个独立脚本）
- `video-compose/`: 视频构图（488 个独立脚本）
- `video-grade/`: 视频调色（488 个独立脚本）
- `video-motion/`: 视频运动（488 个独立脚本）
- `video-quality/`: 视频质量（488 个独立脚本）
- `camera-ingest/`: 相机素材接入（488 个独立脚本）
- `camera-inspect/`: 相机素材检查（488 个独立脚本）
- `media-pipeline/`: 媒体管线检查（8 个独立脚本）

`catalog.tsv` 是 2,000 个脚本的可机读索引。修改预设定义后运行 `python3 generate_media_presets.py`，即可完整重建独立脚本。
