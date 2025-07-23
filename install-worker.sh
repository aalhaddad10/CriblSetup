#!/bin/bash


### START CRIBL LEADER TEMPLATE SETTINGS ###
read -p "Enter Cribl Domain: " DOMAIN
read -p "Enter Auth Token: " TOKEN
read -p "Enter Worker Group: " GROUP
read -p "Is TLS Disabled? (true | false): " TLS
echo "[+] Continuing with Cribl Installation..."

[ -z "${CRIBL_MASTER_HOST}" ]         && CRIBL_MASTER_HOST="$DOMAIN"
[ -z "${CRIBL_AUTH_TOKEN}" ]          && CRIBL_AUTH_TOKEN="$TOKEN"
[ -z "${CRIBL_MASTER_TLS_DISABLED}" ] && CRIBL_MASTER_TLS_DISABLED="$TLS"
[ -z "${CRIBL_VERSION}" ]             && CRIBL_VERSION="$1"
[ -z "${CRIBL_GROUP}" ]               && CRIBL_GROUP="$GROUP"
[ -z "${CRIBL_TAGS}" ]                && CRIBL_TAGS="[]"
[ -z "${CRIBL_MASTER_PORT}" ]         && CRIBL_MASTER_PORT="4200"
[ -z "${CRIBL_DOWNLOAD_URL}" ]        && CRIBL_DOWNLOAD_URL=""
[ -z "${CRIBL_WORKER_MODE}" ]         && CRIBL_WORKER_MODE="worker"
[ -z "${CRIBL_USER}" ]                && CRIBL_USER="cribl"
[ -z "${CRIBL_USER_GROUP}" ]          && CRIBL_USER_GROUP="cribl"
[ -z "${CRIBL_INSTALL_DIR}" ]         && CRIBL_INSTALL_DIR="/opt/cribl"

### END CRIBL LEADER TEMPLATE SETTINGS ###


# Set defaults
checkrun() { type $1 &>/dev/null; }
faildep() { [ $? -eq 127 ] && echo "$1 not found" && exit 1; }
[ -z "${CRIBL_MASTER_HOST}" ] && echo "CRIBL_MASTER_HOST not set" && exit 1
CRIBL_INSTALL_DIR="${CRIBL_INSTALL_DIR:-/opt/cribl}"
CRIBL_MASTER_PORT="${CRIBL_MASTER_PORT:-4200}"
CRIBL_AUTH_TOKEN="${CRIBL_AUTH_TOKEN:-criblmaster}"
CRIBL_MASTER_TLS_DISABLED=${CRIBL_MASTER_TLS_DISABLED:-true}
CRIBL_WORKER_MODE="${CRIBL_WORKER_MODE:-worker}"
CRIBL_USER="${CRIBL_USER:-cribl}"
CRIBL_USER_GROUP="${CRIBL_USER_GROUP:-cribl}"
if [ -z "${CRIBL_GROUP}" ]; then
  if [ "$CRIBL_WORKER_MODE" == "managed-edge" ]; then
    CRIBL_GROUP="default_fleet"
  else
    CRIBL_GROUP="default"
  fi
fi

if [ -z "${CRIBL_DOWNLOAD_URL}" ]; then
    FILE="cribl-${CRIBL_VERSION}-linux-:ARCH:.tgz"
    CRIBL_DOWNLOAD_URL="https://cdn.cribl.io/dl/$(echo ${CRIBL_VERSION} | cut -d '-' -f 1)/${FILE}"
fi
case `uname -m` in
    aarch64) ARCH=arm64;;
    *) ARCH=x64;;
esac
CRIBL_DOWNLOAD_URL=${CRIBL_DOWNLOAD_URL/:ARCH:/$ARCH}

UBUNTU=0
CENTOS=0
AMAZON=0
RHEL=0
DOCKER=0
BOOTSTART=0

INITD=0

echo "Checking dependencies"
checkrun curl && faildep curl
checkrun useradd && faildep useradd
checkrun usermod && faildep usermod

echo -n 'Checking OS version... '
if [ -f /.dockerenv ]; then
    DOCKER=1
    echo Docker
elif grep -qi ubuntu /etc/os-release 2>/dev/null; then
    UBUNTU=1
    echo Ubuntu
elif grep -qi amazon /etc/system-release 2>/dev/null; then
    AMAZON=1
    echo Amazon
elif grep -qi centos /etc/system-release 2>/dev/null; then
    CENTOS=1
    if grep -Eqi 'centos .*release 6\b' /etc/system-release 2>/dev/null; then
        INITD=1
        echo CentOS with initd
    else
        echo CentOS
    fi
elif grep -qi 'red hat' /etc/system-release 2>/dev/null; then
    RHEL=1
    echo Red Hat
else
    echo not recognized
fi

if [ $DOCKER -eq 0 ]; then
  if [ $INITD -eq 1 ]; then
      if checkrun update-rc.d || checkrun chkconfig; then
          BOOTSTART=1
      fi
  elif checkrun systemctl; then
      BOOTSTART=1
  fi
else
  if [ $CRIBL_USER == "cribl" ]; then
    # in docker use whatever user running as, rather than cribl
    CRIBL_USER=$(whoami)
    echo "Running in Docker as user=$CRIBL_USER"
  fi

  if [ "$CRIBL_USER_GROUP" == "cribl" ]; then
    # in docker use the username as group, rather than cribl
    # note we're just about to create this group with useradd -U
    CRIBL_USER_GROUP=$CRIBL_USER
  fi
fi

echo "Creating Cribl user"
useradd "${CRIBL_USER}" -m -U -c "Cribl user"

resolve_group_id() {
  getent group "$1" | awk -F ':' '{print $3}'
}

printf "%s" "Resolving user group \"$CRIBL_USER_GROUP\" to group id: "
CRIBL_USER_GROUP_ID=$(resolve_group_id "$CRIBL_USER_GROUP")
if [[ -z "$CRIBL_USER_GROUP_ID" ]]; then
  echo "(NOT FOUND)"
  printf "  %s" "Creating group \"$CRIBL_USER_GROUP\": "
  if groupadd "$CRIBL_USER_GROUP"; then
    echo "DONE"
    printf "  %s" "Resolving newly created group to group id: "
    CRIBL_USER_GROUP_ID=$(resolve_group_id "$CRIBL_USER_GROUP")
    if [[ -z "$CRIBL_USER_GROUP_ID" ]]; then
      echo "(NOT FOUND, falling back to user group)"
    else
      echo "$CRIBL_USER_GROUP_ID"
    fi
  else
    echo "FAILED"
  fi
else
  echo "$CRIBL_USER_GROUP_ID"
fi

curldownload() {
  local url=$1
  local output=$2
  local status
  status=$(curl -Lso "${output}" --write-out "%{http_code} %{scheme}" "${url}")
  local curl_exit_code=$?
  local http_code=$(cut -d " " -f1 <<< $status)
  local scheme=$(cut -d " " -f2 <<< $status)
  if [[ $scheme = "HTTP" || $scheme = "HTTPS" || $scheme = "FTP" || $scheme = "FTPS" ]] ; then
    if [[ $http_code -lt 200 || $http_code -gt 299 ]] ; then
      echo "error: invalid HTTP status downloading package; url=${url} status=${http_code}" >&2
      return 1
    fi
  fi
  if [[ $curl_exit_code -ne 0 ]] ; then
    echo "error: curl exited with non-zero code; url=${url} code=${curl_exit_code} status=${status}" >&2
    return 1
  fi
  return 0
}
PKG=./cribl.tar.gz
curlpkg() {
  curldownload "${CRIBL_DOWNLOAD_URL}" "${PKG}" && curldownload "${CRIBL_DOWNLOAD_URL}.md5" "${PKG}.md5" || return 1;
  return 0
}
checkpkg() {
  if checkrun md5sum; then
    if [[ "$(md5sum "${PKG}" | awk '{print $1}')" != "$(awk '{print $1}' "${PKG}.md5")" ]]; then
      echo "error: checksum validation failed; package=${PKG}" >&2
      return 1 # fail
    fi
  else
    echo "warning: unable to validate package; missing md5sum" >&2
  fi
  return 0 # success
}

echo "Downloading and Installing Cribl ..."
mkdir -p ${CRIBL_INSTALL_DIR}
if [ ! -f $PKG ]
then
  echo "Downlaoding Cribl From Cribl-CDN"
  curlpkg && checkpkg || { echo "error: aborting installation" >&2; exit 1; }
fi

tar xzf "${PKG}" -C "${CRIBL_INSTALL_DIR}" --strip-components=1
rm -f "${PKG}" "${PKG}.md5"

echo "Configuring Cribl"
mkdir -p ${CRIBL_INSTALL_DIR}/local/_system
cat <<-EOF > ${CRIBL_INSTALL_DIR}/local/_system/instance.yml
distributed:
  mode: ${CRIBL_WORKER_MODE}
  master:
    host: ${CRIBL_MASTER_HOST}
    port: ${CRIBL_MASTER_PORT}
    authToken: ${CRIBL_AUTH_TOKEN}
    tls:
      disabled: ${CRIBL_MASTER_TLS_DISABLED}
  group: ${CRIBL_GROUP}
  tags: ${CRIBL_TAGS:-[]}
EOF

chown -R ${CRIBL_USER}:"${CRIBL_USER_GROUP_ID}" ${CRIBL_INSTALL_DIR}
if [ $BOOTSTART -eq 1 ]; then
    echo "Setting Cribl to start on boot"
    if [ $INITD -eq 1 ]; then
        BOOT_OPTS='-m initd'
    fi
    ${CRIBL_INSTALL_DIR}/bin/cribl boot-start enable -u ${CRIBL_USER} $BOOT_OPTS
fi

chown -R ${CRIBL_USER}:"${CRIBL_USER_GROUP_ID}" ${CRIBL_INSTALL_DIR}
if [ $BOOTSTART -eq 1 ]; then
  [ "$CRIBL_WORKER_MODE" = "worker" ] && SERVICE='cribl' || SERVICE='cribl-edge'
  if [ $INITD -ne 1 ]; then
    service ${SERVICE} start
  else
    /etc/init.d/${SERVICE} start
  fi
else
  echo "${CRIBL_INSTALL_DIR}/bin/cribl start" | su - ${CRIBL_USER}
fi
