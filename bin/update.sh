#!/usr/bin/env bash
set -euo pipefail

# Main update script for the ET AQT data pipeline.
#
# Processes AQT observation CSV files from the Ethiopian data feed into
# csv2qd input format, then calls convert-to-sqd.sh to produce querydata.
#
# Reads site-specific configuration from /smartmet/cnf/data/aqt.cnf
# (or cnf/aqt.cnf in the project directory as fallback).
#
# Required variables (set in .cnf or environment):
#   DATA_RAW_ROOT   - directory containing raw observation CSV files
#   OUTDIR          - directory for intermediate csv2qd input files
#
# Optional variables (with defaults shown):
#   AQT_OBS_PARAMS  - path to obs-param list (default: <script dir>/cnf/aqt-obs-params.txt)
#   STATIONFILE     - path to stations CSV; updated automatically on each run
#                     (default: $BASE/run/data/aqt/cnf/stations.csv)
#   STATION_BASE    - first station number assigned to new stations (default: 90001)

SCRIPTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPODIR="$(cd "$SCRIPTDIR/.." && pwd)"

if [[ -d /smartmet ]]; then
  BASE=/smartmet
else
  BASE=$HOME
fi

CNF="$BASE/cnf/data/aqt.cnf"
if [[ ! -s "$CNF" ]]; then
  CNF="$REPODIR/cnf/aqt.cnf"
fi
if [[ -s "$CNF" ]]; then
  # shellcheck source=/dev/null
  . "$CNF"
fi

AQT_OBS_PARAMS="${AQT_OBS_PARAMS:-$REPODIR/cnf/aqt-obs-params.txt}"
STATIONFILE="${STATIONFILE:-$BASE/run/data/aqt/cnf/stations.csv}"
STATION_BASE="${STATION_BASE:-90001}"

mkdir -p "$OUTDIR"

# --- Update station list ---
# Scan incoming CSV files for new stations and merge into the station file.
# Existing stations are never removed, so stations that are temporarily offline
# remain in the list and retain their station numbers.
echo "Updating station list: $STATIONFILE" >&2
find "$DATA_RAW_ROOT" -type f -name 'observations_*.csv' -print0 \
  | sort -z \
  | xargs -0 -r bash "$SCRIPTDIR/make-stations-csv.sh" \
      --base "$STATION_BASE" \
      --update "$STATIONFILE" \
      --out "$STATIONFILE"

# --- Parse CSV files into csv2qd input ---
AQT_OUT="$OUTDIR/csv2qd_input_aqt.csv"
: > "$AQT_OUT"

echo "Processing ET AQT CSV files from: $DATA_RAW_ROOT" >&2
find "$DATA_RAW_ROOT" -type f -name 'observations_*.csv' -print0 \
  | sort -z \
  | xargs -0 -r -n 100 bash "$SCRIPTDIR/parse-et-aqt-csvtoqd.sh" "$AQT_OBS_PARAMS" \
  >> "$AQT_OUT"

echo "AQT parsed output written to: $AQT_OUT" >&2
bash "$SCRIPTDIR/convert-to-sqd.sh"
