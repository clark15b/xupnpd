#!/usr/bin/env roundup

before() {
  export SRC_DIR="$(pwd)/../src"
  export XUPNPDROOTDIR=`mktemp -d -t "${1:-tmp}.XXXXXX"`
  pushd "$XUPNPDROOTDIR"
  mkdir localmedia plugins recent
  cp -r "$SRC_DIR/config" .
  cp "$SRC_DIR/plugins/xupnpd_$(basename ${BASH_SOURCE%-test.sh})" plugins		# luckily roundup also assumes bash
  cp "$SRC_DIR"/*.lua .
  sed -i -re 's^--(.*[.]/localmedia.*)^\1^' -e "s/UPnP-IPTV/$(basename ${XUPNPDROOTDIR%.*})/" -e 's/(sort_files=).*/\1true/' xupnpd.lua
}

xupnpd() {	# unbuffered IO eases failing test debugging
  stdbuf -i 0 -o 0 -e 0 "$SRC_DIR/xupnpd"${PLATFORM:+-$PLATFORM} "$@"
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
  PLUGIN_NAME="recent"
  sed -i -re 's/core[.]mainloop[(][)]/print("'"$PLUGIN_NAME"' plugin type: " .. type(plugins["'"$PLUGIN_NAME"'"]))/' xupnpd_main.lua		# make our life easier by synchronous execution
  
  xupnpd | lookup "$PLUGIN_NAME plugin type: table"
}

it_symlinks_requested_stream() {
  touch localmedia/0_1_1.avi

  xupnpd &
  
  http stream/0_1_1.avi
  [ -L recent/127.0.0.1/01-0_1_1.avi ]
}

it_preserves_5_symlinks_by_default() {
  seq -f "localmedia/0_1_%1.0f.avi" 1 6 | xargs -t touch

  xupnpd &
  
  for i in $(seq 1 6); do
    http stream/0_1_$i.avi
  done
  [ ! -e recent/127.0.0.1/0[0-9]-0_1_1.avi ] && [ ! -L recent/127.0.0.1/0[0-9]-0_1_1.avi ]
  [ -L recent/127.0.0.1/01-0_1_2.avi ]
  [ -L recent/127.0.0.1/02-0_1_3.avi ]
  [ -L recent/127.0.0.1/03-0_1_4.avi ]
  [ -L recent/127.0.0.1/04-0_1_5.avi ]
  [ -L recent/127.0.0.1/05-0_1_6.avi ]
}

it_uses_configurable_count() {
  touch localmedia/0_1_1.avi
  touch localmedia/0_1_2.avi
  touch localmedia/0_1_3.avi
  sed -i -re "/^cfg[.]recent_count\s*=\s*/ s|[0-9]+|2|" xupnpd.lua

  xupnpd &
  
  http stream/0_1_1.avi
  http stream/0_1_2.avi
  http stream/0_1_3.avi
  [ ! -e recent/127.0.0.1/0[0-9]-0_1_1.avi ] && [ ! -L recent/127.0.0.1/0[0-9]-0_1_1.avi ]
  [ -L recent/127.0.0.1/01-0_1_2.avi ]
  [ -L recent/127.0.0.1/02-0_1_3.avi ]
}

it_uses_configurable_path_with_optional_terminal_slash() {
  touch localmedia/0_1_1.avi
  touch localmedia/0_1_2.avi
  mkdir -p custom_recent_dir/127.0.0.1
  ln -s "$(readlink -f localmedia/0_1_1.avi)" custom_recent_dir/127.0.0.1/01-0_1_1.avi
  sed -i -re "s|^(cfg[.]recent_path\s*=\s*')[^']*('.*)|\1./custom_recent_dir\2|" xupnpd.lua
  
  xupnpd &
  
  http stream/0_1_2.avi
  [ -L custom_recent_dir/127.0.0.1/01-0_1_1.avi ]
  [ -L custom_recent_dir/127.0.0.1/02-0_1_2.avi ]
}

it_uses_ui_entered_path() {
  cp -R "$SRC_DIR/ui" .
  touch localmedia/0_1_1.avi
  touch localmedia/0_1_2.avi
  touch localmedia/0_1_3.avi
  mkdir recent/127.0.0.1 custom_recent_dir
  ln -s "$(readlink -f localmedia/0_1_2.avi)" recent/127.0.0.1/01-0_1_2.avi
  
  xupnpd &
  
  http stream/0_1_1.avi
  [ -L recent/127.0.0.1/01-0_1_2.avi ]
  [ -L recent/127.0.0.1/02-0_1_1.avi ]
  [ -z "$(ls -A custom_recent_dir)" ]

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
recent_path=.%2Fcustom_recent_dir%2F
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
sort_files=true
feeds_update_interval=0
playlists_update_interval=0
drive=
BODY

  http stream/0_1_3.avi
  [ -L custom_recent_dir/127.0.0.1/01-0_1_2.avi ]
  [ -L custom_recent_dir/127.0.0.1/02-0_1_1.avi ]
  [ -L custom_recent_dir/127.0.0.1/03-0_1_3.avi ]
  [ ! -e recent ]
}

it_uses_ui_entered_count() {
  cp -R "$SRC_DIR/ui" .
  seq -f "localmedia/0_1_%1.0f.avi" 1 6 | xargs -t touch
  sed -i -re "/^cfg[.]recent_count\s*=\s*/ s|[0-9]+|2|" xupnpd.lua
  
  xupnpd &
  
  http stream/0_1_1.avi
  http stream/0_1_2.avi
  http stream/0_1_3.avi
  [ ! -e recent/127.0.0.1/0[0-9]-0_1_1.avi ] && [ ! -L recent/127.0.0.1/0[0-9]-0_1_1.avi ]
  [ -L recent/127.0.0.1/01-0_1_2.avi ]
  [ -L recent/127.0.0.1/02-0_1_3.avi ]

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
recent_count=3
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
sort_files=true
feeds_update_interval=0
playlists_update_interval=0
drive=
BODY

  http stream/0_1_3.avi
  [ ! -e recent/127.0.0.1/0[0-9]-0_1_1.avi ] && [ ! -L recent/127.0.0.1/0[0-9]-0_1_1.avi ]
  [ -L recent/127.0.0.1/01-0_1_2.avi ]
  [ -L recent/127.0.0.1/02-0_1_3.avi ]

  http stream/0_1_4.avi
  [ ! -e recent/127.0.0.1/0[0-9]-0_1_1.avi ] && [ ! -L recent/127.0.0.1/0[0-9]-0_1_1.avi ]
  [ -L recent/127.0.0.1/01-0_1_2.avi ]
  [ -L recent/127.0.0.1/02-0_1_3.avi ]
  [ -L recent/127.0.0.1/03-0_1_4.avi ]
}

it_handles_shell_metachars_correctly() {
  sed -i -re "/^cfg[.]recent_count\s*=\s*/ s|[0-9]+|2|" xupnpd.lua
  for SPECIAL in "'" '"' '`' '$' '&' '|' ';' ':' '\\' '*' '!' '+' '#' '(' ')' '{' '}' '[' ']' '<' '>'; do
    seq -f "localmedia/0${SPECIAL}1_%1.0f.avi" 1 3 | tr '\n' '\0' | xargs -0t touch
    
    pgrep xupnpd || xupnpd &
    
    for i in $(seq 1 3); do
      http "stream/0_1_$i.avi"
    done
    
    [ ! -e "recent/127.0.0.1/0[0-9]-0${SPECIAL}1_1.avi" ] && [ ! -L "recent/127.0.0.1/0[0-9]-0${SPECIAL}1_1.avi" ]
    [ -L "recent/127.0.0.1/01-0${SPECIAL}1_2.avi" ]
    [ -L "recent/127.0.0.1/02-0${SPECIAL}1_3.avi" ]
    
    seq -f "localmedia/0${SPECIAL}1_%1.0f.avi" 1 3 | tr '\n' '\0' | xargs -0t rm -f
  done
}
