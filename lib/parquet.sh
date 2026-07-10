# shellcheck shell=bash
#
# parquet.sh — duckdb wrappers for reading parquet row counts, temporal series,
# and column statistics. Every function returns non-zero on a read error
# (truncated/corrupt parquet, missing column) so callers can raise an integrity
# failure with an exact message instead of crashing. Output is pipe-delimited
# (duckdb -list); all values queried here are numeric, so '|' is unambiguous.

# _pq_sql SQL -> run a query, echo rows on success, return duckdb's exit code.
_pq_sql() {
    local sql="$1" out rc
    out=$(duckdb -noheader -list -c "$sql" 2>/dev/null)
    rc=$?
    if (( rc != 0 )); then
        return "$rc"
    fi
    printf '%s\n' "$out"
    return 0
}

# _pq_lit PATH -> SQL single-quoted string literal (escapes embedded quotes).
_pq_lit() {
    local s="${1//\'/\'\'}"
    printf "'%s'" "$s"
}

# _pq_ident NAME -> SQL double-quoted identifier (column names carry dots).
_pq_ident() {
    local s="${1//\"/\"\"}"
    printf '"%s"' "$s"
}

# pq_row_count PARQUET -> echoes the number of rows, or returns 1 on read error.
pq_row_count() {
    local lit; lit=$(_pq_lit "$1")
    _pq_sql "SELECT count(*) FROM read_parquet(${lit});"
}

# pq_columns PARQUET -> echoes one column name per line.
pq_columns() {
    local lit; lit=$(_pq_lit "$1")
    _pq_sql "SELECT name FROM (DESCRIBE SELECT * FROM read_parquet(${lit}));"
}

# pq_temporal PARQUET -> echoes "count|min_ts|max_ts|nonmonotonic|max_gap"
# computed over rows ordered by frame_index. Returns non-zero if the timestamp
# or frame_index column is absent (caller reports it as a temporal failure).
pq_temporal() {
    local lit; lit=$(_pq_lit "$1")
    _pq_sql "
        SELECT count(*), min(timestamp), max(timestamp),
               coalesce(sum(CASE WHEN prev IS NOT NULL AND timestamp <= prev THEN 1 ELSE 0 END), 0),
               coalesce(max(CASE WHEN prev IS NOT NULL THEN timestamp - prev END), 0)
        FROM (SELECT timestamp,
                     lag(timestamp) OVER (ORDER BY frame_index) AS prev
              FROM read_parquet(${lit}));"
}

# pq_array_stats PARQUET COLUMN -> per-dimension stats for a LIST/array column,
# one line each: "index|min|max|mean|std" (population std, matching numpy).
pq_array_stats() {
    local lit ident
    lit=$(_pq_lit "$1"); ident=$(_pq_ident "$2")
    _pq_sql "
        WITH e AS (
            SELECT unnest(${ident}) AS v,
                   generate_subscripts(${ident}, 1) AS i
            FROM read_parquet(${lit})
        )
        SELECT i, min(v), max(v), avg(v), stddev_pop(v)
        FROM e GROUP BY i ORDER BY i;"
}

# pq_scalar_stats PARQUET COLUMN -> "min|max|mean|std" for a scalar column.
pq_scalar_stats() {
    local lit ident
    lit=$(_pq_lit "$1"); ident=$(_pq_ident "$2")
    _pq_sql "
        SELECT min(${ident}), max(${ident}), avg(${ident}), stddev_pop(${ident})
        FROM read_parquet(${lit});"
}

# --- glob variants: one query over every episode parquet (batch efficiency) ---
# All take a GLOB like "<root>/data/**/*.parquet" and use duckdb's filename=true
# so each output row is tagged with its source file. This turns N per-episode
# queries (N=501 for the largest dataset) into a single duckdb invocation.

# pq_row_counts_glob GLOB -> "filepath|rows" per episode parquet.
pq_row_counts_glob() {
    local lit; lit=$(_pq_lit "$1")
    _pq_sql "SELECT filename, count(*)
             FROM read_parquet(${lit}, filename = true)
             GROUP BY filename;"
}

# pq_temporal_glob GLOB -> "filepath|count|min_ts|max_ts|nonmonotonic|max_gap"
# per episode, timestamps ordered by frame_index within each file.
pq_temporal_glob() {
    local lit; lit=$(_pq_lit "$1")
    _pq_sql "
        WITH t AS (
            SELECT filename, timestamp,
                   lag(timestamp) OVER (PARTITION BY filename ORDER BY frame_index) AS prev
            FROM read_parquet(${lit}, filename = true)
        )
        SELECT filename, count(*), min(timestamp), max(timestamp),
               coalesce(sum(CASE WHEN prev IS NOT NULL AND timestamp <= prev THEN 1 ELSE 0 END), 0),
               coalesce(max(CASE WHEN prev IS NOT NULL THEN timestamp - prev END), 0)
        FROM t GROUP BY filename;"
}

# pq_array_stats_whole GLOB COLUMN -> "index|min|max|mean|std" aggregated over
# EVERY row in all files (not per episode) — used to validate the global
# stats.json of v2.0 datasets.
pq_array_stats_whole() {
    local lit ident
    lit=$(_pq_lit "$1"); ident=$(_pq_ident "$2")
    _pq_sql "
        WITH e AS (
            SELECT unnest(${ident}) AS v,
                   generate_subscripts(${ident}, 1) AS i
            FROM read_parquet(${lit})
        )
        SELECT i, min(v), max(v), avg(v), stddev_pop(v)
        FROM e GROUP BY i ORDER BY i;"
}

# pq_array_stats_glob GLOB COLUMN -> "filepath|index|min|max|mean|std" per
# episode and per array dimension, for one LIST/array column across all files.
pq_array_stats_glob() {
    local lit ident
    lit=$(_pq_lit "$1"); ident=$(_pq_ident "$2")
    _pq_sql "
        WITH e AS (
            SELECT filename,
                   unnest(${ident}) AS v,
                   generate_subscripts(${ident}, 1) AS i
            FROM read_parquet(${lit}, filename = true)
        )
        SELECT filename, i, min(v), max(v), avg(v), stddev_pop(v)
        FROM e GROUP BY filename, i ORDER BY filename, i;"
}
