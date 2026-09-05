#!/bin/zsh
set -euo pipefail

if ! command -v ffmpeg >/dev/null 2>&1; then
  print -u2 "需要 ffmpeg。可用 Homebrew 安装：brew install ffmpeg"
  exit 1
fi

output_root=${1:-"${PWD}/MockVideoLibraries-$(date +%Y%m%d-%H%M%S)"}
script_dir=${0:A:h}

if [[ -e "${output_root}" && ! -d "${output_root}" ]]; then
  print -u2 "输出路径已存在且不是文件夹：${output_root}"
  exit 1
fi

if [[ -d "${output_root}" ]]; then
  existing_item=$(find "${output_root}" -mindepth 1 -maxdepth 1 -print -quit)
  if [[ -n "${existing_item}" ]]; then
    print -u2 "输出文件夹必须为空，避免旧文件污染测试场景：${output_root}"
    print -u2 "请不带参数运行以创建带时间戳的新目录，或指定一个新的空目录。"
    exit 1
  fi
fi

temporary_dir=$(mktemp -d "${TMPDIR:-/tmp}/bilingual-video-mocks.XXXXXX")
trap 'rm -rf "${temporary_dir}"' EXIT
xcrun swiftc "${script_dir}/render_title_card.swift" -o "${temporary_dir}/render-title-card"
card_index=0

make_video() {
  local output_path=$1
  local color=$2
  local label=$3
  local frequency=$4
  local card_path="${temporary_dir}/card-${card_index}.png"
  card_index=$((card_index + 1))

  mkdir -p "${output_path:h}"
  "${temporary_dir}/render-title-card" "${card_path}" "${color}" "${label}"
  ffmpeg -hide_banner -loglevel error -y \
    -loop 1 -i "${card_path}" \
    -f lavfi -i "sine=frequency=${frequency}:duration=3" \
    -t 3 -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest "${output_path}"
}

make_pair() {
  local scenario=$1
  local chinese_name=$2
  local english_name=$3
  local id_label=$4

  make_video "${output_root}/${scenario}/Chinese/${chinese_name}.mp4" "D1495B" "CHINESE ${id_label} TEST" 440
  make_video "${output_root}/${scenario}/English/${english_name}.mp4" "277DA1" "ENGLISH ${id_label} TEST" 660
}

mkdir -p "${output_root}"

make_pair normal 005 5 005
make_pair normal 20 020 020
make_pair normal 100 100 100

make_pair missing-side 005 005 005
make_video "${output_root}/missing-side/Chinese/020.mp4" "D1495B" "CHINESE 020 ONLY" 440

make_video "${output_root}/duplicate-id/Chinese/5.mp4" "D1495B" "CHINESE 5 TEST" 440
make_video "${output_root}/duplicate-id/Chinese/005.mp4" "F4A261" "CHINESE 005 DUPLICATE" 500
make_video "${output_root}/duplicate-id/English/5.mp4" "277DA1" "ENGLISH 5 TEST" 660

make_pair invalid-items 100 100 100
make_video "${output_root}/invalid-items/Chinese/abc.mp4" "6D597A" "INVALID NAME" 520
print "not a video" > "${output_root}/invalid-items/English/notes.txt"

print "测试资源已生成：${output_root}"
print "场景：normal、missing-side、duplicate-id、invalid-items"
