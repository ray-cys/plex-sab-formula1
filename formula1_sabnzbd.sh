#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# NZB RSS Feed Keywords: formula1 "year"
# Sabnzbd RSS Filters:
# 0 : Requires : MWR
# 1 : Reject : re: proper|notebook|multi
# 2 : Requires : re: F1TV|SKY
# 3 : Requires : re: re: FP1|FP2|FP3|Sprint|Qualifying|Race|Pre|Post|Warm-Up|Conference|Morning|Afternoon|Post-Testing|Round00|Wrap-Up
# 4 : Reject : re: 720p|2160p
# 5 : Accept : *

# Set preferred feed to SKY or F1LIVE
PREFERRED_FEED="F1LIVE"

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
for KEY in "${!EPISODE_ARRAY[@]}"; do
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
