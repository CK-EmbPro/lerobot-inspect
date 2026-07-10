# shellcheck shell=bash
#
# flag_cross_dataset_anomalies.sh — cross-dataset outlier detection (check 13).
# In a batch, flag any dataset whose fps deviates from the batch median fps by
# more than RATIO. This is a heuristic hint, not a per-dataset verdict, and is
# only meaningful with >= 3 datasets.

# flag_cross_dataset_anomalies DATASETS_ARRAY RATIO -> JSON array of anomaly strings.
flag_cross_dataset_anomalies() {
    local datasets="$1" ratio="$2"
    jq -c --argjson ratio "$ratio" '
        def fabs: if . < 0 then - . else . end;
        def median:
            (sort) as $s | ($s | length) as $n
            | if $n == 0 then null
              elif $n % 2 == 1 then $s[($n - 1) / 2]
              else ($s[$n/2 - 1] + $s[$n/2]) / 2 end;
        . as $ds
        | if ($ds | length) < 3 then []
          else
            ([ $ds[] | .stats.fps | select(. != null and . > 0) ]) as $fps
            | ($fps | median) as $mf
            | [ $ds[]
                | select(.stats.fps != null and $mf != null and $mf > 0
                         and ((((.stats.fps - $mf) / $mf) | fabs) > $ratio))
                | "\(.path): fps=\(.stats.fps) deviates from batch median \($mf)" ]
          end
    ' <<< "$datasets"
}
