#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./make-stations-csv.sh [--base NUM] [--update EXISTING_CSV] [--out FILE] observations_*.csv
#
# Reads AQT observation CSV files, extracts station coordinates from embedded
# LATITUDE_DEGREES_VALUE_PT0S_1 and LONGITUDE_DEGREES_VALUE_PT0S_1 rows,
# and writes a stations.csv suitable for csv2qd -S.
#
# Without --update: generates a fresh stations.csv from the input files.
# With --update EXISTING_CSV: preserves all stations already in EXISTING_CSV
#   (including stations currently offline) and appends any new stations found
#   in the input files with the next available station numbers.
#
# Output format: station_id,station_number,longitude,latitude,"Station Name"
#
# Options:
#   --base NUM          starting station number for a fresh file (default: 90001)
#   --update FILE       merge into existing FILE; never remove entries
#   --out FILE          write output to FILE instead of stdout (atomic rename)

BASE=90001
OUT="-"
UPDATE_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base)   BASE="${2:?--base requires a number}";   shift 2 ;;
    --out)    OUT="${2:?--out requires a filename}";   shift 2 ;;
    --update) UPDATE_FILE="${2:?--update requires a filename}"; shift 2 ;;
    --)       shift; break ;;
    -*)       echo "Unknown option: $1" >&2; exit 1 ;;
    *)        break ;;
  esac
done

[[ $# -ge 1 ]] || { echo "No input files given" >&2; exit 2; }

_run_awk() {
  awk -v base="$BASE" -v update_file="$UPDATE_FILE" '
    function make_name(id,    name) {
      name = id
      sub(/_AQT$/, "", name)
      gsub(/_/, " ", name)
      return name
    }

    BEGIN {
      FS = ";"
      nexisting = 0
      max_num   = base - 1

      # Load existing stations when in update mode
      if (update_file != "" && (getline line < update_file) >= 0) {
        # File opened successfully; rewind by closing and re-reading
        close(update_file)
        while ((getline line < update_file) > 0) {
          if (line ~ /^[[:space:]]*$/ || line ~ /^#/) continue
          # Format: station_id,station_number,longitude,latitude,"name"
          n = split(line, f, ",")
          if (n < 4) continue
          sid  = f[1]
          num  = int(f[2])
          slon = f[3]
          slat = f[4]
          sname = ""
          for (i = 5; i <= n; i++) sname = sname (i > 5 ? "," : "") f[i]
          gsub(/^"/, "", sname)
          gsub(/"$/,  "", sname)

          existing_num[sid]  = num
          existing_lon[sid]  = slon
          existing_lat[sid]  = slat
          existing_name[sid] = sname
          nexisting++
          existing_order[nexisting] = sid

          if (num > max_num) max_num = num
        }
        close(update_file)
      }

      nnew = 0
    }

    {
      for (i = 1; i <= NF; i++) gsub(/"/, "", $i)

      station = $1
      obs_id  = $3
      value   = $6

      if (station == "" || obs_id == "" || value == "" || value == "///") next

      if (obs_id == "LATITUDE_DEGREES_VALUE_PT0S_1" && !(station in new_lat_seen)) {
        new_lat[station]      = value
        new_lat_seen[station] = 1
        if (!(station in existing_num) && !(station in new_order)) {
          nnew++
          new_order[station] = nnew
          new_list[nnew]     = station
        }
      }

      if (obs_id == "LONGITUDE_DEGREES_VALUE_PT0S_1" && !(station in new_lon_seen)) {
        new_lon[station]      = value
        new_lon_seen[station] = 1
        if (!(station in existing_num) && !(station in new_order)) {
          nnew++
          new_order[station] = nnew
          new_list[nnew]     = station
        }
      }
    }

    END {
      # Emit existing stations unchanged
      for (i = 1; i <= nexisting; i++) {
        s = existing_order[i]
        printf "%s,%d,%s,%s,\"%s\"\n",
          s, existing_num[s], existing_lon[s], existing_lat[s], existing_name[s]
      }

      # Collect new stations that have both lat and lon
      nvalid = 0
      for (i = 1; i <= nnew; i++) {
        s = new_list[i]
        if ((s in new_lat_seen) && (s in new_lon_seen)) {
          nvalid++
          valid[nvalid] = s
        } else {
          print "Warning: skipping " s " (missing lat or lon)" > "/dev/stderr"
        }
      }

      # Sort new stations alphabetically for stable number assignment
      for (i = 1; i <= nvalid; i++) {
        for (j = i + 1; j <= nvalid; j++) {
          if (valid[i] > valid[j]) {
            tmp = valid[i]; valid[i] = valid[j]; valid[j] = tmp
          }
        }
      }

      for (i = 1; i <= nvalid; i++) {
        s   = valid[i]
        num = max_num + i
        printf "%s,%d,%s,%s,\"%s\"\n",
          s, num, new_lon[s], new_lat[s], make_name(s)
        print "Added new station: " s " (" num ")" > "/dev/stderr"
      }
    }
  ' "$@"
}

if [[ "$OUT" == "-" ]]; then
  _run_awk "$@"
else
  OUTDIR="$(dirname "$OUT")"
  mkdir -p "$OUTDIR"
  TMPFILE="$(mktemp "$OUTDIR/.stations_tmp.XXXXXX")"
  _run_awk "$@" > "$TMPFILE"
  mv -f "$TMPFILE" "$OUT"
  echo "Station list written to $OUT" >&2
fi
