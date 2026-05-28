#!/usr/bin/env bash
set -euo pipefail

# Parse ET AQT observation CSV files into csv2qd input format.
#
# Usage:
#   ./parse-et-aqt-csvtoqd.sh aqt-obs-params.txt observations_*.csv > csv2qd_input.csv
#
# Input CSV format (semicolon-delimited, all fields double-quoted, no header):
#   station_id ; timestamp ; param_name ; param_group ; unit ; value ; height ; agg_type ; period
#
# Example row:
#   "Abune_Bacillos_AQT";"2026-05-27T06:48:00.841";"AIR_TEMPERATURE_DEGREES_CELSIUS_MEAN_PT1M_1";"AIR_TEMPERATURE";"DEGREES_CELSIUS";"18.9";"0.0";"MEAN";"PT1M"
#
# Output: one row per (station_id, timestamp) with parameter values in the order
# defined by aqt-obs-params.txt, suitable as input to csv2qd with -O idtime.
#
# Missing/fill values (-9999.9, 9999.9, ///, /) are emitted as empty fields.

PARAMS_FILE="${1:?Usage: $0 aqt-obs-params.txt observations_*.csv}"
shift
[[ $# -ge 1 ]] || { echo "No input files given" >&2; exit 2; }
[[ -r "$PARAMS_FILE" ]] || { echo "Cannot read params file: $PARAMS_FILE" >&2; exit 1; }

# Resolve before awk changes working directory
PARAMS_FILE_ABS="$(realpath "$PARAMS_FILE")"

for f in "$@"; do
  [[ -r "$f" ]] || { echo "Skipping unreadable file: $f" >&2; continue; }

  awk -v params_file="$PARAMS_FILE_ABS" '
    BEGIN {
      FS = ";"

      n = 0
      while ((getline p < params_file) > 0) {
        gsub(/\r/, "", p)
        sub(/^[ \t]+/, "", p)
        sub(/[ \t]+$/, "", p)
        if (p == "" || p ~ /^#/) continue
        n++
        want[n]    = p
        wantidx[p] = n
      }
      close(params_file)
      if (n == 0) { print "No parameters loaded from " params_file > "/dev/stderr"; exit 1 }

      nrec = 0
    }

    {
      for (i = 1; i <= NF; i++) gsub(/"/, "", $i)

      station = $1
      ts      = $2
      param   = $3
      val     = $6

      if (!(param in wantidx)) next

      sub(/T/, " ", ts)
      sub(/\.[0-9]+$/, "", ts)

      key = station SUBSEP ts
      if (!(key in seen)) {
        nrec++
        recstation[nrec] = station
        rects[nrec]      = ts
        seen[key]        = nrec
      }

      idx = seen[key]

      if (val == "-9999.9" || val == "9999.9" || val == "///" || val == "/") val = ""

      pval[idx, wantidx[param]] = val
    }

    END {
      for (r = 1; r <= nrec; r++) {
        printf "%s,%s", recstation[r], rects[r]
        for (i = 1; i <= n; i++) {
          if ((r, i) in pval) printf ",%s", pval[r, i]
          else                printf ","
        }
        printf "\n"
      }
    }
  ' "$f"
done
