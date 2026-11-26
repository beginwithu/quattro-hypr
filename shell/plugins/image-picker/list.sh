#!/bin/bash

image_dirs=${1:-}
cache_dir=${XDG_CACHE_HOME:-$HOME/.cache}/quattro/image-selector
index_file="$cache_dir/index.tsv"
pending_video_file=$(mktemp)

mkdir -p "$cache_dir"
trap 'rm -f "$pending_video_file"' EXIT

declare -A thumb_index=()
declare -A image_sigs=()
declare -A thumb_path_cache=()

if [[ -r $index_file ]]; then
  while IFS=$'\t' read -r idx_path idx_sig idx_hash _; do
    [[ -n $idx_path && -n $idx_sig && -n $idx_hash ]] || continue
    [[ -n ${thumb_index["$idx_path"$'\t'"$idx_sig"]+set} ]] || thumb_index["$idx_path"$'\t'"$idx_sig"]=$idx_hash
  done < "$index_file"
fi

is_video_path() {
  [[ ${1,,} =~ \.(mp4|m4v|mov|webm|mkv|avi)$ ]]
}

thumbnail_path_for() {
  local image="$1"
  local signature hash

  if [[ -n ${thumb_path_cache[$image]+set} ]]; then
    REPLY=${thumb_path_cache[$image]}
    [[ -n $REPLY ]]
    return
  fi

  if [[ -n ${image_sigs[$image]+set} ]]; then
    signature=${image_sigs[$image]}
  else
    signature=$(stat -Lc '%s:%Y' "$image" 2>/dev/null) || {
      thumb_path_cache[$image]=""
      return 1
    }
    image_sigs[$image]=$signature
  fi

  hash=${thumb_index["$image"$'\t'"$signature"]-}
  if [[ -z $hash ]]; then
    read -r hash _ < <(printf '%s\t%s' "$image" "$signature" | md5sum)
  fi

  REPLY="$cache_dir/$hash.jpg"
  thumb_path_cache[$image]=$REPLY
}

generate_video_thumbnail() {
  local image="$1"
  local thumbnail="$2"
  local lock="$thumbnail.lock"
  local lock_fd now lock_mtime
  local tmp="$thumbnail.$$.jpg"

  if [[ -d $lock ]]; then
    printf -v now '%(%s)T' -1
    lock_mtime=$(stat -c '%Y' "$lock" 2>/dev/null || printf '%s' "$now")
    if (( now - lock_mtime > 120 )); then
      rmdir "$lock" 2>/dev/null
    fi
  fi

  exec {lock_fd}>"$lock" || return
  flock -w 30 "$lock_fd" || return
  rm -f "$thumbnail".*.jpg

  [[ -f $thumbnail ]] && return

  if timeout -k 5 10 ffmpegthumbnailer -i "$image" -o "$tmp" -s 1536 -q 8 {lock_fd}>&-; then
    mv -f "$tmp" "$thumbnail"
  else
    status=$?
    rm -f "$tmp" "$thumbnail"
    # Remember a rejected video so it costs nothing on the next scan; the key
    # covers size and mtime, so a repaired file starts clean. A timeout is
    # left to retry: the machine may only have been busy.
    (( status == 124 || status == 137 )) || : >"$thumbnail.failed"
    return 1
  fi
}

drain_pending_video_thumbnails() {
  local video_jobs

  [[ -s $pending_video_file ]] || return 0

  video_jobs=$(( $(nproc) / 4 ))
  (( video_jobs > 0 )) || video_jobs=1
  export -f generate_video_thumbnail
  xargs -a "$pending_video_file" -0 -n 2 -P "$video_jobs" \
    bash -c 'generate_video_thumbnail "$1" "$2"' _ >/dev/null 2>&1 || true
}

thumbnail_for() {
  local image="$1"
  local thumbnail legacy_hash

  thumbnail_path_for "$image" || return
  thumbnail=$REPLY

  if [[ ! -f $thumbnail ]] && ! is_video_path "$image"; then
    # Older on-demand picker code keyed fallback thumbnails by file content.
    # Keep finding those if a user still has them cached.
    read -r legacy_hash _ < <(md5sum "$image" 2>/dev/null)
    [[ -n $legacy_hash && -f $cache_dir/$legacy_hash.jpg ]] && thumbnail="$cache_dir/$legacy_hash.jpg"
  fi

  if [[ -f $thumbnail ]]; then
    REPLY=$thumbnail
  elif ! is_video_path "$image"; then
    REPLY=$image
  else
    REPLY=""
  fi
}

mapfile -d '' -t images < <(
  while IFS= read -r dir; do
    [[ -n $dir && -d $dir ]] || continue
    find -L "$dir" -maxdepth 1 -type f \
      \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' -o -iname '*.bmp' -o -iname '*.webp' \
         -o -iname '*.mp4' -o -iname '*.m4v' -o -iname '*.mov' -o -iname '*.webm' -o -iname '*.mkv' -o -iname '*.avi' \) \
      -print0 2>/dev/null
  done <<<"$image_dirs" | sort -z
)

if (( ${#images[@]} > 0 )); then
  mapfile -t batched_sigs < <(stat -Lc '%s:%Y' -- "${images[@]}" 2>/dev/null) || true
  if (( ${#batched_sigs[@]} == ${#images[@]} )); then
    for idx in "${!images[@]}"; do
      image_sigs[${images[$idx]}]=${batched_sigs[$idx]}
    done
  fi
fi

for image in "${images[@]}"; do
  if is_video_path "$image"; then
    thumbnail_path_for "$image" || continue
    thumbnail=$REPLY
    [[ -f $thumbnail || -f $thumbnail.failed ]] || printf '%s\0%s\0' "$image" "$thumbnail" >>"$pending_video_file"
  fi
done

drain_pending_video_thumbnails

for image in "${images[@]}"; do
  REPLY=""
  thumbnail_for "$image" || continue
  [[ -n $REPLY ]] || continue
  printf '%s\t%s\n' "$image" "$REPLY"
done
