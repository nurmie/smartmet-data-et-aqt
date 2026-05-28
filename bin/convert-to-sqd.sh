#!/usr/bin/env bash
set -euo pipefail

# Convert parsed ET AQT obs CSV data to SmartMet querydata format.
#
# Usage:
#   ./convert-to-sqd.sh
#
# Reads site-specific configuration from /smartmet/cnf/data/aqt.cnf
# (or cnf/aqt.cnf in the project directory as fallback).
# Variables already exported in the environment take precedence over .cnf values.
#
# Configuration variables:
#   STATIONFILE  - path to stations CSV (station_id,station_number,lon,lat,name)
#   PARAMFILE    - path to parameters CSV mapping SmartMet parameter definitions
#   OUT          - directory for final querydata output
#   EDITOR       - SmartMet editor inbox directory
#   PARAMS       - comma-separated SmartMet parameter names (must match aqt-obs-params.txt order)
#   PRODNUM      - csv2qd product number (default: 1001)
#   PRODNAME     - csv2qd product name (default: SYNOP)

DATASET="aqt"

SCRIPTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPODIR="$(cd "$SCRIPTDIR/.." && pwd)"

if [[ -d /smartmet ]]; then
  BASE=/smartmet
else
  BASE=$HOME
fi

CNF="$BASE/cnf/data/${DATASET}.cnf"
if [[ ! -s "$CNF" ]]; then
  CNF="$REPODIR/cnf/${DATASET}.cnf"
fi
if [[ -s "$CNF" ]]; then
  # shellcheck source=/dev/null
  . "$CNF"
fi

TMP="${TMP:-$BASE/tmp/data/aqt}"
EDITOR="${EDITOR:-$BASE/editor/in}"
LOGFILE="${LOGFILE:-$BASE/logs/data/aqt.log}"
TIMESTAMP="$(date +%Y%m%d%H%M)"

OUT="${OUT:-$BASE/data/aqt/querydata}"
OBSFILE="$TMP/${TIMESTAMP}_aqt.sqd"
STATIONFILE="${STATIONFILE:-$BASE/run/data/aqt/cnf/stations.csv}"
PARAMFILE="${PARAMFILE:-$REPODIR/cnf/parameters.csv}"
INFILE="${CSV2QD_INPUT:-$TMP/csv2qd_input_aqt.csv}"
# Must match order in cnf/aqt-obs-params.txt
PARAMS="${PARAMS:-Temperature,Humidity,Pressure,WindSpeedMS,WindDirection,Precipitation1h}"
PRODNUM="${PRODNUM:-1001}"
PRODNAME="${PRODNAME:-SYNOP}"

mkdir -p "$TMP" "$OUT"

if [[ "${TERM:-dumb}" == "dumb" ]]; then
  exec &>> "$LOGFILE"
fi

echo "DATASET:  $DATASET"
echo "IN:       $INFILE"
echo "OUT:      $OUT"
echo "OBS file: $OBSFILE"

csv2qd -v \
  --prodnum "$PRODNUM" \
  --prodname "$PRODNAME" \
  -S "$STATIONFILE" \
  -O idtime \
  -P "$PARAMFILE" \
  -p "$PARAMS" \
  "$INFILE" \
  "$OBSFILE"

if [[ -s "$OBSFILE" ]]; then
  pbzip2 -k "$OBSFILE"
  mv -f "$OBSFILE" "$OUT/"
  mv -f "${OBSFILE}.bz2" "$EDITOR/"
fi

rm -f "$INFILE"
