#!/usr/bin/env roundup

before() {
  export SRC_DIR="$(pwd)/../../src"
  export XUPNPDROOTDIR=`mktemp -d -t "${1:-tmp}.XXXXXX"`
  pushd "$XUPNPDROOTDIR"
  mkdir localmedia plugins profiles
  cp "$SRC_DIR/plugins/xupnpd_$(basename ${BASH_SOURCE%-test.sh})" plugins
  cp "$SRC_DIR"/*.lua .
  sed -i -re 's^--(.*[.]/localmedia.*)^\1^' -e "s/UPnP-IPTV/$(basename ${XUPNPDROOTDIR%.*})/" xupnpd.lua
}

xupnpd() {	# unbuffered IO eases failing test debugging
  stdbuf -i 0 -o 0 -e 0 "$SRC_DIR/xupnpd" "$@"
}

lookup() {	# regex; like grep, but prints first match on success, everything when failed
  awk -v "PATT=$*" '$0 ~ PATT {found=1;lines=$0;exit} lines {lines=lines""RS""$0;next} {lines=$0} END {printf(lines);exit(1-found)}'
}

http() {	# /url_path?query [curl args]
  URL="$1" && shift
  curl --silent --retry 5 --retry-connrefused --retry-delay 1 "$@" "http://localhost:4044/${URL#/}"
}

after() {
  pkill xupnpd || true		# $! is empty :-(
  TMP_DIR=`dirs +0`
  popd
  rm -r "$TMP_DIR"
}

it_loads_plugin_at_startup() {
  PLUGIN_NAME="profiles"
  sed -i -re 's/core[.]mainloop[(][)]/print("'"$PLUGIN_NAME"' plugin type: " .. type(plugins["'"$PLUGIN_NAME"'"]))/' xupnpd_main.lua		# make our life easier by synchronous execution
  
  xupnpd | lookup "$PLUGIN_NAME plugin type: table"
}

it_changes_profile_per_user_agent() {
  sed -re 's/Skeleton/profile1/' -e '/disabled/d' -e 's/User-Agent of Device/profile1/' "$SRC_DIR"/profiles/skel/skel.lua > profiles/profile1.lua
  sed -re 's/Skeleton/profile2/' -e '/disabled/d' -e 's/User-Agent of Device/profile2/' -e 's^video/avi^text/html^' "$SRC_DIR"/profiles/skel/skel.lua > profiles/profile2.lua
  touch localmedia/0_1_1.avi

  xupnpd &
  
  http stream/0_1_1.avi --head --user-agent 'profile1' | awk '$0 ~ "Content-Type: video/avi"{found=1} {print} END{exit(1 - found)}'
  http stream/0_1_1.avi --head --user-agent 'profile2' | awk '$0 ~ "Content-Type: text/html"{found=1} {print} END{exit(1 - found)}'
}
