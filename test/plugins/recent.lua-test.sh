#!/usr/bin/env roundup

before() {
  export SRC_DIR="$(pwd)/../src"
  export XUPNPDROOTDIR=`mktemp -d -t "${1:-tmp}.XXXXXX"`
  pushd "$XUPNPDROOTDIR"
  mkdir localmedia plugins recent
  cp -r "$SRC_DIR/config" .
  cp "$SRC_DIR/plugins/xupnpd_$(basename ${BASH_SOURCE%-test.sh})" plugins		# luckily roundup also assumes bash
  cp "$SRC_DIR"/*.lua .
  sed -i -re 's^--(.*Local Media Files.*)^\1^' -e "s/UPnP-IPTV/$(basename ${XUPNPDROOTDIR%.*})/" xupnpd.lua
}

xupnpd() {	# unbuffered IO eases failing test debugging
  stdbuf -i 0 -o 0 -e 0 "$SRC_DIR/xupnpd"${PLATFORM:+-$PLATFORM} "$@"
}

lookup() {	# [-F] [-A n] regex; like grep, but prints first match on success, everything when failed
  AFTER=0
  REGEX=1
  [ "$1" = "-FA" ] && REGEX=0 && AFTER=$2 && shift && shift
  [ "$REGEX" -eq 1 -a "$1" = "-F" ] && REGEX=0 && shift
  [ "$AFTER" -eq 0 -a "$1" = "-A" ] && AFTER=$2 && shift && shift 
  awk -v "AFTER=$AFTER" -v "REGEX=$REGEX" -v "PATT=$*" '
    REGEX == 1 && $0 ~ PATT {found=1;lines=$0;if(AFTER==0)exit;next}
    REGEX == 0 && index($0, PATT) {found=1;lines=$0;if(AFTER==0)exit;next}
    lines {lines=lines""RS""$0;if(found&&--AFTER==0)exit;next}
    {lines=$0}
    END {print(lines);exit(1-found)}
  '
}

http() {	# /url_path?query [curl args]
  URL="$1" && shift
  curl --silent -4 --retry 5 --retry-connrefused --retry-delay 1 "$@" --include "http://localhost:4044/${URL#/}"
}

browse() {	# objid
  cat <<XML | http soap/cds --data-binary '@-' --header 'Content-Type: text/xml; charset="utf-8"' --header "SOAPAction: urn:schemas-upnp-org:service:ContentDirectory:1#Browse"
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
<s:Body><u:Browse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">
<ObjectID>$1</ObjectID>
<BrowseFlag>BrowseDirectChildren</BrowseFlag>
<Filter>*</Filter>
<StartingIndex>0</StartingIndex>
<RequestedCount>5000</RequestedCount>
<SortCriteria></SortCriteria>
</u:Browse>
</s:Body>
</s:Envelope>
XML
}

in_tag() {
  awk "-F(</?$1[^>]*>)+" '{for(i=2;i<NF;i=i+1) print $i}'
}

in_DIDL_lite() {
  in_tag Result | perl -MHTML::Entities -pe 'decode_entities($_);' | in_tag DIDL-Lite
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

it_forces_sort_files() {
  touch localmedia/second.avi
  touch localmedia/first.mp4
  touch localmedia/terminal.avi
  touch localmedia/second_last.mkv
  
  xupnpd &
  
  browse 0 | in_DIDL_lite | lookup '<container id="0_1" childCount="4" parentID="0" restricted="true"><dc:title>Local Media Files</dc:title><upnp:class>object.container</upnp:class></container>'
  browse 0_1 | in_DIDL_lite | in_tag item | \
    lookup -FA 3 '<dc:title>first</dc:title><upnp:class>object.item.videoItem</upnp:class><res size="0" protocolInfo="http-get:*:video/mp4:*">http://127.0.0.1:4044/stream/0_1_1.mp4</res>' | \
    lookup -FA 2 '<dc:title>second</dc:title><upnp:class>object.item.videoItem</upnp:class><res size="0" protocolInfo="http-get:*:video/avi:DLNA.ORG_PN=PV_DIVX_DX50;DLNA.ORG_OP=01;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01700000000000000000000000000000">http://127.0.0.1:4044/stream/0_1_2.avi</res>' | \
    lookup -FA 1 '<dc:title>second_last</dc:title><upnp:class>object.item.videoItem</upnp:class><res size="0" protocolInfo="http-get:*:video/x-matroska:*">http://127.0.0.1:4044/stream/0_1_3.mkv</res>' | \
    lookup -FA 0 '<dc:title>terminal</dc:title><upnp:class>object.item.videoItem</upnp:class><res size="0" protocolInfo="http-get:*:video/avi:DLNA.ORG_PN=PV_DIVX_DX50;DLNA.ORG_OP=01;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01700000000000000000000000000000">http://127.0.0.1:4044/stream/0_1_4.avi</res>'
}

it_symlinks_media_most_recent_first() {
  touch localmedia/0_1_1.avi localmedia/0_1_2.avi

  xupnpd &
  
  http stream/0_1_1.avi | lookup 'HTTP/1.1 200 OK'
  [ -L recent/127.0.0.1/01-0_1_1.avi ] && ls -l recent/127.0.0.1/01-0_1_1.avi | lookup '^.*localmedia/0_1_1[.]avi$'

  http stream/0_1_2.avi | lookup 'HTTP/1.1 200 OK'
  [ -L recent/127.0.0.1/01-0_1_2.avi ] && ls -l recent/127.0.0.1/01-0_1_2.avi | lookup '^.*localmedia/0_1_2[.]avi$'
  [ -L recent/127.0.0.1/02-0_1_1.avi ] && ls -l recent/127.0.0.1/02-0_1_1.avi | lookup '^.*localmedia/0_1_1[.]avi$'
}

it_preserves_5_symlinks_by_default() {
  seq -f "localmedia/0_1_%1.0f.avi" 1 6 | xargs -t touch

  xupnpd &
  
  for i in $(seq 1 6); do
    http stream/0_1_$i.avi | lookup 'HTTP/1.1 200 OK'
  done
  [ ! -e recent/127.0.0.1/0[0-9]-0_1_1.avi ] && [ ! -L recent/127.0.0.1/0[0-9]-0_1_1.avi ]
  for i in $(seq 2 6); do
    [ -L "recent/127.0.0.1/0$((7-$i))-0_1_$i.avi" ] && ls -l "recent/127.0.0.1/0$((7-$i))-0_1_$i.avi" | lookup "^.*localmedia/0_1_$i"'[.]avi$'
  done
}

it_updates_item_position_when_played_again() {
  it_preserves_5_symlinks_by_default

  http stream/0_2_4.avi | lookup 'HTTP/1.1 200 OK'

  [ ! -e recent/127.0.0.1/0[0-9]-0_1_1.avi ] && [ ! -L recent/127.0.0.1/0[0-9]-0_1_1.avi ]
  [ -L recent/127.0.0.1/05-0_1_2.avi ] && ls -l recent/127.0.0.1/05-0_1_2.avi | lookup '^.*localmedia/0_1_2[.]avi$'
  [ -L recent/127.0.0.1/04-0_1_4.avi ] && ls -l recent/127.0.0.1/04-0_1_4.avi | lookup '^.*localmedia/0_1_4[.]avi$'
  [ -L recent/127.0.0.1/03-0_1_5.avi ] && ls -l recent/127.0.0.1/03-0_1_5.avi | lookup '^.*localmedia/0_1_5[.]avi$'
  [ -L recent/127.0.0.1/02-0_1_6.avi ] && ls -l recent/127.0.0.1/02-0_1_6.avi | lookup '^.*localmedia/0_1_6[.]avi$'
  [ -L recent/127.0.0.1/01-0_1_3.avi ] && ls -l recent/127.0.0.1/01-0_1_3.avi | lookup '^.*localmedia/0_1_3[.]avi$'
}

it_uses_configurable_count() {
  touch localmedia/0_1_1.avi
  touch localmedia/0_1_2.avi
  touch localmedia/0_1_3.avi
  sed -i -re "/^cfg[.]recent_count\s*=\s*/ s|[0-9]+|2|" xupnpd.lua

  xupnpd &
  
  http stream/0_1_1.avi | lookup 'HTTP/1.1 200 OK'
  http stream/0_1_2.avi | lookup 'HTTP/1.1 200 OK'
  http stream/0_1_3.avi | lookup 'HTTP/1.1 200 OK'
  [ ! -e recent/127.0.0.1/0[0-9]-0_1_1.avi ] && [ ! -L recent/127.0.0.1/0[0-9]-0_1_1.avi ]
  [ -L recent/127.0.0.1/02-0_1_2.avi ] && ls -l recent/127.0.0.1/02-0_1_2.avi | lookup '^.*localmedia/0_1_2[.]avi$'
  [ -L recent/127.0.0.1/01-0_1_3.avi ] && ls -l recent/127.0.0.1/01-0_1_3.avi | lookup '^.*localmedia/0_1_3[.]avi$'
}

it_uses_configurable_path_with_optional_terminal_slash() {
  touch localmedia/0_1_1.avi
  touch localmedia/0_1_2.avi
  mkdir -p custom_recent_dir/127.0.0.1
  ln -s "$(readlink -f localmedia/0_1_1.avi)" custom_recent_dir/127.0.0.1/01-0_1_1.avi
  sed -i -re "s|^(cfg[.]recent_path\s*=\s*')[^']*('.*)|\1./custom_recent_dir\2|" xupnpd.lua
  
  xupnpd &
  
  http stream/0_1_2.avi | lookup 'HTTP/1.1 200 OK'
  [ -L custom_recent_dir/127.0.0.1/02-0_1_1.avi ] && ls -l custom_recent_dir/127.0.0.1/02-0_1_1.avi | lookup '^.*localmedia/0_1_1[.]avi$'
  [ -L custom_recent_dir/127.0.0.1/01-0_1_2.avi ] && ls -l custom_recent_dir/127.0.0.1/01-0_1_2.avi | lookup '^.*localmedia/0_1_2[.]avi$'
}

config_payload() {
  cat <<BODY
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
}

it_uses_ui_entered_path() {
  cp -R "$SRC_DIR/ui" .
  touch localmedia/0_1_1.avi
  touch localmedia/0_1_2.avi
  touch localmedia/0_1_3.avi
  mkdir recent/127.0.0.1 custom_recent_dir
  ln -s "$(readlink -f localmedia/0_1_2.avi)" recent/127.0.0.1/01-0_1_2.avi
  
  xupnpd &
  
  http stream/0_1_1.avi | lookup 'HTTP/1.1 200 OK'
  [ -L recent/127.0.0.1/02-0_1_2.avi ] && ls -l recent/127.0.0.1/02-0_1_2.avi | lookup '^.*localmedia/0_1_2[.]avi$'
  [ -L recent/127.0.0.1/01-0_1_1.avi ] && ls -l recent/127.0.0.1/01-0_1_1.avi | lookup '^.*localmedia/0_1_1[.]avi$'
  [ -z "$(ls -A custom_recent_dir)" ]

  ( config_payload ; echo 'recent_path=.%2Fcustom_recent_dir%2F/' ) | tr '\n' '&' | http ui/apply --data-binary '@-'

  http stream/0_1_3.avi | lookup 'HTTP/1.1 200 OK'
  [ -L custom_recent_dir/127.0.0.1/03-0_1_2.avi ] && ls -l custom_recent_dir/127.0.0.1/03-0_1_2.avi | lookup '^.*localmedia/0_1_2[.]avi$'
  [ -L custom_recent_dir/127.0.0.1/02-0_1_1.avi ] && ls -l custom_recent_dir/127.0.0.1/02-0_1_1.avi | lookup '^.*localmedia/0_1_1[.]avi$'
  [ -L custom_recent_dir/127.0.0.1/01-0_1_3.avi ] && ls -l custom_recent_dir/127.0.0.1/01-0_1_3.avi | lookup '^.*localmedia/0_1_3[.]avi$'
  [ ! -e recent ]
}

it_uses_ui_entered_count() {
  cp -R "$SRC_DIR/ui" .
  seq -f "localmedia/0_1_%1.0f.avi" 1 6 | xargs -t touch
  sed -i -re "/^cfg[.]recent_count\s*=\s*/ s|[0-9]+|2|" xupnpd.lua
  
  xupnpd &
  
  http stream/0_1_1.avi | lookup 'HTTP/1.1 200 OK'
  http stream/0_1_2.avi | lookup 'HTTP/1.1 200 OK'
  http stream/0_1_3.avi | lookup 'HTTP/1.1 200 OK'
  [ ! -e recent/127.0.0.1/0[0-9]-0_1_1.avi ] && [ ! -L recent/127.0.0.1/0[0-9]-0_1_1.avi ]
  [ -L recent/127.0.0.1/02-0_1_2.avi ] && ls -l recent/127.0.0.1/02-0_1_2.avi | lookup '^.*localmedia/0_1_2[.]avi$'
  [ -L recent/127.0.0.1/01-0_1_3.avi ] && ls -l recent/127.0.0.1/01-0_1_3.avi | lookup '^.*localmedia/0_1_3[.]avi$'

  ( config_payload ; echo 'recent_count=3' ) | tr '\n' '&' | http ui/apply --data-binary '@-'

  http stream/0_1_3.avi | lookup 'HTTP/1.1 200 OK'
  [ ! -e recent/127.0.0.1/0[0-9]-0_1_1.avi ] && [ ! -L recent/127.0.0.1/0[0-9]-0_1_1.avi ]
  [ -L recent/127.0.0.1/02-0_1_2.avi ] && ls -l recent/127.0.0.1/02-0_1_2.avi | lookup '^.*localmedia/0_1_2[.]avi$'
  [ -L recent/127.0.0.1/01-0_1_3.avi ] && ls -l recent/127.0.0.1/01-0_1_3.avi | lookup '^.*localmedia/0_1_3[.]avi$'

  http stream/0_1_4.avi | lookup 'HTTP/1.1 200 OK'
  [ ! -e recent/127.0.0.1/0[0-9]-0_1_1.avi ] && [ ! -L recent/127.0.0.1/0[0-9]-0_1_1.avi ]
  [ -L recent/127.0.0.1/03-0_1_2.avi ] && ls -l recent/127.0.0.1/03-0_1_2.avi | lookup '^.*localmedia/0_1_2[.]avi$'
  [ -L recent/127.0.0.1/02-0_1_3.avi ] && ls -l recent/127.0.0.1/02-0_1_3.avi | lookup '^.*localmedia/0_1_3[.]avi$'
  [ -L recent/127.0.0.1/01-0_1_4.avi ] && ls -l recent/127.0.0.1/01-0_1_4.avi | lookup '^.*localmedia/0_1_4[.]avi$'
}

it_handles_shell_metachars_correctly() {
  sed -i -re "/^cfg[.]recent_count\s*=\s*/ s|[0-9]+|2|" xupnpd.lua
  for SPECIAL in "'" '"' '`' '$' '&' '|' ';' ':' '\' '*' '!' '+' '#' '(' ')' '{' '}' '[' ']' '<' '>'; do
    seq -f "localmedia/0${SPECIAL}1_%1.0f.avi" 1 3 | tr '\n' '\0' | xargs -0t touch
    
    xupnpd &
    
    for i in $(seq 1 3); do
      http "stream/0_1_$i.avi" | lookup 'HTTP/1.1 200 OK'
    done
    
    [ ! -e "recent/127.0.0.1/0[0-9]-0${SPECIAL}1_1.avi" ] && [ ! -L "recent/127.0.0.1/0[0-9]-0${SPECIAL}1_1.avi" ] # lookup -F '...' has trouble with backslash
    [ -L "recent/127.0.0.1/02-0${SPECIAL}1_2.avi" ] && ls -l "recent/127.0.0.1/02-0${SPECIAL}1_2.avi" | grep -F "$(pwd)/localmedia/0${SPECIAL}1_2.avi"
    [ -L "recent/127.0.0.1/01-0${SPECIAL}1_3.avi" ] && ls -l "recent/127.0.0.1/01-0${SPECIAL}1_3.avi" | grep -F "$(pwd)/localmedia/0${SPECIAL}1_3.avi"
    
    seq -f "localmedia/0${SPECIAL}1_%1.0f.avi" 1 3 | tr '\n' '\0' | xargs -0t rm -f
    rm -vf "recent/127.0.0.1/01-0${SPECIAL}1_3.avi" "recent/127.0.0.1/02-0${SPECIAL}1_2.avi"
    kill $!
  done
}
