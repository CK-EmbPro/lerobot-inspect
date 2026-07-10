# Broken-dataset test harness (Deliverable #2)

The brief requires a test that **generates broken datasets and proves the tool
catches each**. Build it read-only-safe: copy a known-good dataset to a temp dir,
then perturb the copy — never mutate the original.

## Corruptions to inject (one fixture per check)

| Fixture                | Perturbation                                         | Check it must trip |
|------------------------|------------------------------------------------------|--------------------|
| `drop_frame`           | Re-encode one mp4 with one fewer frame               | 7 cross-modal      |
| `truncate_parquet`     | `truncate -s -1024` on an episode parquet            | 7 / robustness     |
| `corrupt_info`         | Write invalid JSON into `meta/info.json`             | malformed JSON     |
| `delete_chunk`         | `rm` a whole `data/chunk-000` or one video dir       | 8 missing files    |
| `orphan_file`          | Add an unreferenced `episode_999999.parquet`         | 8 orphan files     |
| `wrong_total`          | Set `total_episodes` to a wrong value                | 9 metadata         |
| `zero_field`           | Set `fps` to 0 / empty                               | 9 invalid field    |
| `time_gap`             | Perturb `timestamp` so it's non-monotonic            | 10 temporal        |
| `perturb_stat`         | Shift a stored mean beyond tolerance                 | 11 statistical     |
| `zero_byte_video`      | `: > episode_000000.mp4`                             | robustness/exit 2  |

## Expected behavior

For every fixture: the tool must **exit non-zero**, name the **exact episode/file**,
and **never print PASS**. A fixture that produces exit 0 or a crash is a test
failure. Assert on both the exit code and a substring of the message.

## Skeleton

```bash
run_case() {
  local name="$1" expect_code="$2"
  local out; out=$(./lerobot-inspect "$FIXTURE_DIR/$name" 2>&1); local code=$?
  if [ "$code" -eq 0 ]; then
    echo "FAIL[$name]: tool reported PASS on broken data" >&2; return 1
  fi
  if [ "$code" -ne "$expect_code" ]; then
    echo "FAIL[$name]: exit $code, expected $expect_code" >&2; return 1
  fi
  echo "ok[$name]: caught (exit $code)"
}
```

Pair this with the [`qa-expert`](../../agents/qa-expert.md) and
[`code-reviewer`](../../agents/code-reviewer.md) agents for a mutation-testing
mindset: if flipping a `>` to `>=` in a check wouldn't fail a fixture, add one.
