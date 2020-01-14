#!/usr/bin/env roundup

before() {
  export SRC_DIR="$(pwd)/../src"
  export XUPNPDROOTDIR=`mktemp -d -t "${1:-tmp}.XXXXXX"`
  pushd "$XUPNPDROOTDIR"
  mkdir localmedia plugins profiles
  cp -r "$SRC_DIR/config" .
  cp "$SRC_DIR/plugins/xupnpd_$(basename ${BASH_SOURCE%-test.sh})" plugins		# luckily roundup also assumes bash
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
  curl --silent -4 --retry 5 --retry-connrefused --retry-delay 1 "$@" "http://localhost:4044/${URL#/}"
}

after() {
  pkill xupnpd || true		# $! is empty :-(; true prevents failure on synchronous tests
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
  
  http stream/0_1_1.avi --head --user-agent 'profile1' | lookup "Content-Type: video/avi"
  http stream/0_1_1.avi --head --user-agent 'profile2' | lookup "Content-Type: text/html"
}

it_uses_configurable_path() {
  mkdir custom_profiles_dir
  sed -re 's/Skeleton/profile1/' -e '/disabled/d' -e 's/User-Agent of Device/profile1/' -e 's^video/avi^text/html^' "$SRC_DIR"/profiles/skel/skel.lua > custom_profiles_dir/profile1.lua
  sed -i -re "s|^(cfg[.]profiles\s*=\s*')[^']*('.*)|\1./custom_profiles_dir/\2|" xupnpd.lua
  touch localmedia/0_1_1.avi
  
  xupnpd &
  
  http stream/0_1_1.avi --head --user-agent 'profile1' | lookup "Content-Type: text/html"
}

it_uses_ui_entered_path() {
  cp -R "$SRC_DIR/ui" .
  mkdir custom_profiles_dir
  sed -re 's/Skeleton/profile2/' -e '/disabled/d' -e 's/User-Agent of Device/profile2/' -e 's^video/avi^text/html^' "$SRC_DIR"/profiles/skel/skel.lua > custom_profiles_dir/profile2.lua
  touch localmedia/0_1_1.avi
  
  xupnpd &
  
  http stream/0_1_1.avi --head --user-agent 'profile1' | lookup "Content-Type: video/avi"

  cat <<BODY | tr '\n' '&' | http ui/apply --data-binary '@-'
vk_private_workaround=true
vk_video_count=100
youtube_fmt=37
youtube_region=*
youtube_video_count=100
vimeo_fmt=hd
vimeo_video_count=100
ivi_fmt=MP4-hi
ivi_video_count=100
ag_fmt=400p
gametrailers_video_count=100
profiles=.%2Fcustom_profiles_dir%2F
name=UPnP-IPTV
uuid=60bd2fb3-dabe-cb14-c766-0e319b54c29a
default_mime_type=mpeg
ssdp_interface=lo
ssdp_notify_interval=15
ssdp_max_age=1800
http_port=4044
user_agent=Mozilla%2F5.0
http_timeout=30
mcast_interface=eth1
proxy=2
dlna_notify=true
dlna_subscribe_ttl=1800
group=true
sort_files=false
feeds_update_interval=0
playlists_update_interval=0
drive=
BODY

  http stream/0_1_1.avi --head --user-agent 'profile2' | lookup "Content-Type: text/html"
}
