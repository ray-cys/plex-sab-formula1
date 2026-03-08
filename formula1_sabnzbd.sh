#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# NZB RSS Feed Keywords: formula1 "year"
# Sabnzbd RSS Filters:
# 0 : Requires : MWR
# 1 : Reject : re: proper|notebook|multi
# 2 : Requires : re: F1TV|F1LIVE
# 3 : Requires : re: re: FP1|FP2|FP3|Sprint|Qualifying|Race|Pre|Post|Warm-Up|Conference|Morning|Afternoon|Post-Testing|Round00|Wrap-Up
# 4 : Reject : re: 720p|2160p|SKY
# 5 : Accept : *

# Set preferred feed SKY or F1TV
PREFERRED_FEED="F1TV"

# Set destination dir where to place processed files.
# Must be accessible from Sabnzbd container if running in docker
DEST_DIR="/data/formula1"

# Set Sabnzbd variables
SRC_DIR="$1"
JOB_NAME="$3"
SAB_FILE=$(find "$SRC_DIR" -type f | sort -n | tail -1)
EXTENSION="${SAB_FILE##*.}"
NEW_FILENAME="${JOB_NAME}.${EXTENSION}"

echo "=== Sabnzbd F1 script starting ==="
echo "Job name: ${JOB_NAME}"
echo "Source dir: ${SRC_DIR}"
echo "Selected file: ${SAB_FILE}"
echo "New filename: ${NEW_FILENAME}"

# Handle pre-season testing (Round00) as Plex specials (Season 00)
if echo "${NEW_FILENAME}" | grep -qE "\.Round00\."; then
  echo "Detected pre-season testing (Round00)."

  OLD_IFS="$IFS"
  IFS='.'
  read -ra PARTS <<< "${NEW_FILENAME}"
  IFS="$OLD_IFS"
  YEAR="${PARTS[1]}"
  SEASON="00"
  LOCATION="${PARTS[3]}"
  TEST_SET_WORD=""
  DAY_WORD=""
  TIME_WORD=""

  # Find the index of the "Test"/"Testing" token
  TEST_IDX=-1
  for i in "${!PARTS[@]}"; do
    if [[ "${PARTS[$i]}" == "Test" || "${PARTS[$i]}" == "Testing" ]]; then
      TEST_IDX=$i
      break
    fi
  done

  if (( TEST_IDX >= 0 )); then
    NEXT_TOKEN="${PARTS[$((TEST_IDX+1))]:-}"
    case "${NEXT_TOKEN}" in
      One|Two|Three)
        TEST_SET_WORD="${NEXT_TOKEN}"
        TEST_IDX=$((TEST_IDX+1))
        ;;
    esac

    if [[ "${PARTS[$((TEST_IDX+1))]:-}" == "Day" ]]; then
      DAY_WORD="${PARTS[$((TEST_IDX+2))]:-}"
      if [[ "${PARTS[$((TEST_IDX+3))]:-}" == "Morning" || "${PARTS[$((TEST_IDX+3))]:-}" == "Afternoon" ]]; then
        TIME_WORD="${PARTS[$((TEST_IDX+3))]:-}"
      fi
    fi
  fi

  # Map words to numeric indices for deterministic episode numbering
  TEST_INDEX=1
  case "${TEST_SET_WORD}" in
    One) TEST_INDEX=1 ;;
    Two) TEST_INDEX=2 ;;
    Three) TEST_INDEX=3 ;;
  esac

  DAY_INDEX=0
  case "${DAY_WORD}" in
    One) DAY_INDEX=1 ;;
    Two) DAY_INDEX=2 ;;
    Three) DAY_INDEX=3 ;;
  esac

  TIME_CODE=0
  case "${TIME_WORD}" in
    Morning) TIME_CODE=1 ;;
    Afternoon) TIME_CODE=2 ;;
  esac

  # Compute a stable S00E## for testing sessions
  if (( DAY_INDEX == 0 )); then
    EPISODE_NUM=$(((TEST_INDEX - 1) * 10 + 9))
  else
    BASE=$(((TEST_INDEX - 1) * 10 + (DAY_INDEX - 1) * 2))
    if (( TIME_CODE == 0 )); then
      EPISODE_NUM=$((BASE + 1))
    else
      EPISODE_NUM=$((BASE + TIME_CODE))
    fi
  fi

  EPISODE=$(printf '%02d' "${EPISODE_NUM}")

  DESCRIPTION="Testing"
  [[ -n "${TEST_SET_WORD}" ]] && DESCRIPTION+=" ${TEST_SET_WORD}"
  [[ -n "${DAY_WORD}" ]] && DESCRIPTION+=" Day ${DAY_WORD}"
  [[ -n "${TIME_WORD}" ]] && DESCRIPTION+=" ${TIME_WORD}"

  PLEX_DIR="${DEST_DIR}/F1 ${YEAR}/Season ${SEASON}"
  PLEX_NAME="S${SEASON}E${EPISODE} - ${LOCATION} Pre-Season Testing - ${DESCRIPTION}"
  PLEX_FILENAME="${PLEX_NAME}.${EXTENSION}"
  mkdir -p "${PLEX_DIR}"

  # Detect network/feed tag directly from filename
  NETWORK=$(echo "${NEW_FILENAME}" | grep -Eo 'F1TV|F1LIVE|SKY' | head -1 || true)
  echo "Detected network/feed tag: ${NETWORK:-Unknown}"

  if echo "${NETWORK}" | grep -qEio "${PREFERRED_FEED}"; then
    echo "File is Preferred Network (${PREFERRED_FEED})."
    echo "Moving file to: ${PLEX_DIR}/${PLEX_FILENAME}"
    mv "${SAB_FILE}" "${PLEX_DIR}/${PLEX_FILENAME}"
  else
    if [ ! -f "${PLEX_DIR}/${PLEX_FILENAME}" ]; then
      echo "File is not Preferred Feed (${PREFERRED_FEED}) and file does not exist."
      echo "Moving file to: ${PLEX_DIR}/${PLEX_FILENAME}"
      mv "${SAB_FILE}" "${PLEX_DIR}/${PLEX_FILENAME}"
    else
      echo "File is not Preferred Feed (${PREFERRED_FEED}) and file already exists."
      echo "Skipped"
      echo "Non-preferred duplicate skipped; existing file kept: ${PLEX_DIR}/${PLEX_FILENAME}"
      rm -rf "${SRC_DIR}"
      exit 0
    fi
  fi

  echo "Cleaning up sabnzbd files"
  rm -rf "${SRC_DIR}"

  echo "Setting permissions for ${PLEX_DIR}/${PLEX_FILENAME}"
  chmod 774 "${PLEX_DIR}/${PLEX_FILENAME}"
  echo "Completed job for ${PLEX_FILENAME} in ${PLEX_DIR}"
  echo "=== Sabnzbd F1 script finished (pre-season) ==="
  exit 0
fi

# Array of episodes names and episode number for Plex naming.
declare -A EPISODE_ARRAY
EPISODE_ARRAY["Weekend.Warm-Up"]="01"
EPISODE_ARRAY["FP1"]="02"
EPISODE_ARRAY["Sprint.Qualifying"]="03"
EPISODE_ARRAY["Pre-Sprint.Show"]="04"
EPISODE_ARRAY["Sprint"]="05"
EPISODE_ARRAY["Post-Sprint.Show"]="06"
EPISODE_ARRAY["FP2"]="07"
EPISODE_ARRAY["FP3"]="08"
EPISODE_ARRAY["Pre-Qualifying.Show"]="09"
EPISODE_ARRAY["Qualifying"]="10"
EPISODE_ARRAY["Post-Qualifying.Show"]="11"
EPISODE_ARRAY["Pre-Race.Show"]="12"
EPISODE_ARRAY["Race"]="13"
EPISODE_ARRAY["Post-Race.Show"]="14"
EPISODE_ARRAY["Post-Race.Press.Conference"]="15"

# Check if filename contains the episodes array assigned
FOUND=0
EPISODE_KEYS=$(printf '%s\n' "${!EPISODE_ARRAY[@]}" | awk '{print length, $0}' | sort -nr | cut -d' ' -f2-)
for KEY in ${EPISODE_KEYS}; do
  PATTERN="${KEY//./[ .-]}"
  if echo "${NEW_FILENAME}" | grep -qEio "${PATTERN}"; then
    FOUND=1
    printf 'Matched episode key: %s -> E%s\n' "${KEY}" "${EPISODE_ARRAY["${KEY}"]}"
    break
  fi
done

# Filename does not contain wanted episode name, stop and delete files
if [[ $FOUND -eq 0 ]]; then
  echo "Filename does not contain wanted episode criteria"
  echo "Aborted"
  rm -rf "${SRC_DIR}"
  exit 0
fi

# Extract info for Plex naming: YEAR, SEASON, EPISODE, LOCATION
YEAR=$(echo "${NEW_FILENAME}" | cut -d. -f2)
SEASON=$(echo "${NEW_FILENAME}" | cut -d. -f3 | sed 's/Round//')
EPISODE="${EPISODE_ARRAY["${KEY}"]}"
LOCATION=$(echo "${NEW_FILENAME}" | cut -d. -f4)
echo "Parsed metadata - YEAR: ${YEAR}, SEASON: ${SEASON}, EPISODE: ${EPISODE}, LOCATION: ${LOCATION}"

# Define new directory and filename for Plex, create directories if needed
PLEX_DIR="${DEST_DIR}/F1 ${YEAR}/Season ${SEASON}"
PLEX_NAME="S${SEASON}E${EPISODE} - ${LOCATION} Grand Prix - ${KEY}"
PLEX_FILENAME="${PLEX_NAME}.${EXTENSION}"
mkdir -p "${PLEX_DIR}"

# Check network feed and decide if to keep the file or not based on preferred feed and if file already exists
NETWORK=$(echo "${NEW_FILENAME}" | sed -n "s/.*${KEY}.//Ip" | sed 's/.WEB.*//')
echo "Detected network/feed tag: ${NETWORK}"

if echo "${NETWORK}" | grep -qEio "${PREFERRED_FEED}"; then
  echo "File is Preferred Network (${PREFERRED_FEED})."
  echo "Moving file to: ${PLEX_DIR}/${PLEX_FILENAME}"
  mv "${SAB_FILE}" "${PLEX_DIR}/${PLEX_FILENAME}"
else
  if [ ! -f "${PLEX_DIR}/${PLEX_FILENAME}" ]; then
    echo "File is not Preferred Feed (${PREFERRED_FEED}) and file does not exist."
    echo "Moving file to: ${PLEX_DIR}/${PLEX_FILENAME}"
    mv "${SAB_FILE}" "${PLEX_DIR}/${PLEX_FILENAME}"
  else
    echo "File is not Preferred Feed (${PREFERRED_FEED}) and file already exists."
    echo "Skipped"
    echo "Non-preferred duplicate skipped; existing file kept: ${PLEX_DIR}/${PLEX_FILENAME}"
    rm -rf "${SRC_DIR}"
    exit 0
  fi
fi

# Remove unwanted files
echo "Cleaning up sabnzbd files"
rm -rf "${SRC_DIR}"

# Set files and directories permissions
echo "Setting permissions for ${PLEX_DIR}/${PLEX_FILENAME}"
chmod 774 "${PLEX_DIR}/${PLEX_FILENAME}"
echo "Completed job for ${PLEX_FILENAME} in ${PLEX_DIR}"
echo "=== Sabnzbd F1 script finished ==="

exit 0
