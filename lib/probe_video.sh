# shellcheck shell=bash
#
# probe_video.sh — ffprobe wrappers. Frame counts come from the video stream, never
# from the filename (the brief's rule). Two strategies, chosen by
# LEROBOT_INSPECT_FRAME_MODE: "fast" reads the container's nb_frames header
# (~12x faster); "exact" decodes every packet. fast auto-falls-back to exact
# when the header count is absent (e.g. N/A on some variable-frame encodings).

# video_frame_count MP4 -> echoes an unsigned frame count, or returns 1 if the
# stream is unreadable (corrupt/zero-byte/no video stream).
video_frame_count() {
    local mp4="$1" n=""

    if [[ "${LEROBOT_INSPECT_FRAME_MODE:-fast}" != "exact" ]]; then
        n=$(ffprobe -v error -select_streams v:0 \
            -show_entries stream=nb_frames -of csv=p=0 "$mp4" 2>/dev/null)
    fi

    if [[ ! "$n" =~ ^[0-9]+$ ]]; then
        n=$(ffprobe -v error -select_streams v:0 -count_frames \
            -show_entries stream=nb_read_frames -of csv=p=0 "$mp4" 2>/dev/null)
    fi

    [[ "$n" =~ ^[0-9]+$ ]] || return 1
    echo "$n"
}

# video_resolution MP4 -> echoes "WIDTHxHEIGHT", or returns 1 if unreadable.
video_resolution() {
    local mp4="$1" res
    res=$(ffprobe -v error -select_streams v:0 \
        -show_entries stream=width,height -of csv=s=x:p=0 "$mp4" 2>/dev/null)
    [[ "$res" =~ ^[0-9]+x[0-9]+$ ]] || return 1
    echo "$res"
}
