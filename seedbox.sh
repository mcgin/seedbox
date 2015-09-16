#!/bin/bash
#wget --no-check-certificate https://raw.githubusercontent.com/mcgin/seedbox/master/seedbox.sh

while getopts "p:u:" opt; do
  case $opt in
    p)
        PASSWORD=$OPTARG;;
    u)
		USERNAME=$OPTARG;;
  esac
done

set -e

if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
  echo "usage: $0 -p PASSWORD -u USERNAME"
  exit
fi

apt-get -y update && apt-get -y upgrade

apt-get -y install whois #Install mkpasswd
useradd -mU --password $(mkpasswd -s -m md5 $PASSWORD) --shell /bin/bash $USERNAME
addgroup $USERNAME sudo
groupadd sshdusers
addgroup $USERNAME sshdusers

#Remove existing settings
grep -v '^AllowUsers .*' /etc/ssh/sshd_config > /etc/ssh/sshd_config.tmp; mv /etc/ssh/sshd_config.tmp /etc/ssh/sshd_config
grep -v '^AllowGroups .*' /etc/ssh/sshd_config > /etc/ssh/sshd_config.tmp; mv /etc/ssh/sshd_config.tmp /etc/ssh/sshd_config
grep -v '^Port .*' /etc/ssh/sshd_config > /etc/ssh/sshd_config.tmp; mv /etc/ssh/sshd_config.tmp /etc/ssh/sshd_config
grep -v '^PermitRootLogin .*' /etc/ssh/sshd_config > /etc/ssh/sshd_config.tmp; mv /etc/ssh/sshd_config.tmp /etc/ssh/sshd_config
grep -v '^UseDNS .*' /etc/ssh/sshd_config > /etc/ssh/sshd_config.tmp; mv /etc/ssh/sshd_config.tmp /etc/ssh/sshd_config
grep -v '^Protocol .*' /etc/ssh/sshd_config > /etc/ssh/sshd_config.tmp; mv /etc/ssh/sshd_config.tmp /etc/ssh/sshd_config
grep -v '^X11Forwarding .*' /etc/ssh/sshd_config > /etc/ssh/sshd_config.tmp; mv /etc/ssh/sshd_config.tmp /etc/ssh/sshd_config

#Append new settings to sshd_config
echo "UseDNS no" >>/etc/ssh/sshd_config
echo "AllowGroups $USERNAME" >>/etc/ssh/sshd_config
echo "Port 21976" >>/etc/ssh/sshd_config
echo "PermitRootLogin no" >>/etc/ssh/sshd_config
echo "X11Forwarding no" >>/etc/ssh/sshd_config
echo "Protocol 2" >>/etc/ssh/sshd_config

#restart ssh daemon
service ssh reload

#Install dependencies
apt-get install -y build-essential unzip git subversion autoconf screen g++ gcc ntp curl comerr-dev pkg-config cfv libtool libssl-dev libncurses5-dev ncurses-term libsigc++-2.0-dev libcppunit-dev libcurl3 libcurl4-openssl-dev libpcre3-dev libpcre3 php5-cli php5-fpm

#Install xmlrpc
svn co -q https://svn.code.sf.net/p/xmlrpc-c/code/stable /tmp/xmlrpc-c
pushd /tmp/xmlrpc-c
./configure --disable-libwww-client --disable-wininet-client --disable-abyss-server --disable-cgi-server
make -j2
make install
popd
rm -r /tmp/xmlrpc-c
#sudo -s -- <<EOF 
# Install libTorrent
git clone https://github.com/rakshasa/libtorrent.git /tmp/libtorrent-0.13.4
pushd /tmp/libtorrent-0.13.4
git checkout -b build 0.13.4
./autogen.sh
./configure
make -j2
make install
popd
rm -r /tmp/libtorrent-0.13.4

# install rtorrent
git clone https://github.com/rakshasa/rtorrent.git /tmp/rtorrent-0.9.4
pushd /tmp/rtorrent-0.9.4
git checkout -b build 0.9.4
./autogen.sh
./configure --with-xmlrpc-c
make -j2
make install
ldconfig
popd
rm -r /tmp/rtorrent-0.9.4


mkdir -p /home/downloads/{.session,~watch}
chown -R $USERNAME:$USERNAME /home/downloads

cat <<'EOF' > /home/$USERNAME/.rtorrent.rc
min_peers = 40
max_peers = 100
min_peers_seed = 25
max_peers_seed = 60
max_uploads = 30
directory = /home/downloads
session = /home/downloads/.session
schedule = watch_directory,5,5,load_start=/home/downloads/.watch/*.torrent
schedule = untied_directory,5,5,stop_untied=
schedule = low_diskspace,5,60,close_low_diskspace=10240M
port_range = 55950-56000
port_random = yes
check_hash = yes
use_udp_trackers = yes
encryption = allow_incoming,enable_retry,prefer_plaintext
dht = disable
peer_exchange = no
scgi_port = 127.0.0.1:5000
EOF

chown -R $USERNAME:$USERNAME /home/$USERNAME/.rtorrent.rc


cat <<'EOF' > /etc/init.d/rtorrent
#!/bin/bash
### BEGIN INIT INFO
# Provides:          rtorrent
# Required-Start:    $local_fs $remote_fs $network $syslog
# Required-Stop:     $local_fs $remote_fs $network $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Start/stop rtorrent daemon
### END INIT INFO
USER=BOOM

## Absolute path to the rtorrent binary.
## run "which rtorrent"
RTORRENT="/usr/local/bin/rtorrent"

## Absolute path to the screen binary.
SCREEN="/usr/bin/screen"

## Name of the screen session, you can then "screen -r rtorrent" to get it back
## to the foreground and work with it on your shell.
SCREEN_NAME="rtorrent"

## Absolute path to rtorrent's PID file.
PIDFILE="/var/run/rtorrent.pid"

## Absolute path to rtorrent's XMLRPC socket.
SOCKET="/var/run/rtorrent/rpc.socket"

## Check if the socket exists and if it exists delete it.
delete_socket() {
if [[ -e $SOCKET ]]; then
rm -f $SOCKET
fi
}

case "$1" in
## Start rtorrent in the background.
start)
echo "Starting rtorrent."
delete_socket
start-stop-daemon --start --background --oknodo \
--pidfile "$PIDFILE" --make-pidfile \
--chuid $USER \
--exec $SCREEN -- -DmUS $SCREEN_NAME $RTORRENT
if [[ $? -ne 0 ]]; then
echo "Error: rtorrent failed to start."
exit 1
fi
echo "rtorrent started successfully."
;;

## Stop rtorrent.
stop)
echo "Stopping rtorrent."
start-stop-daemon --stop --oknodo --pidfile "$PIDFILE"
if [[ $? -ne 0 ]]; then
echo "Error: failed to stop rtorrent process."
exit 1
fi
delete_socket
echo "rtorrent stopped successfully."
;;

## Restart rtorrent.
restart)
"$0" stop
sleep 1
"$0" start || exit 1
;;

## Print usage information if the user gives an invalid option.
*)
echo "Usage: $0 [start|stop|restart]"
exit 1
;;

esac
EOF

sed -i "/^USER=BOOM/c\USER=$USERNAME" /etc/init.d/rtorrent
chmod +x /etc/init.d/rtorrent
update-rc.d rtorrent defaults 99

## nginx 
#https://www.digitalocean.com/community/tutorials/how-to-compile-nginx-from-source-on-a-centos-6-4-x64-vps
#http://www.juanjchong.com/2014/setting-up-rtorrentrutorrent-on-ubuntu-14-04-using-ngnix/
#https://www.linode.com/docs/websites/nginx/how-to-install-nginx-on-debian-7-wheezy

adduser --system --no-create-home --group --shell /sbin/nologin nginx

wget -O /tmp/nginx-1.8.0.tar.gz http://nginx.org/download/nginx-1.8.0.tar.gz
tar -xf /tmp/nginx-1.8.0.tar.gz -C /tmp
pushd /tmp/nginx-1.8.0
./configure \
--user=nginx                          \
--group=nginx                         \
--prefix=/etc/nginx                   \
--sbin-path=/usr/sbin/nginx           \
--conf-path=/etc/nginx/nginx.conf     \
--pid-path=/var/run/nginx.pid         \
--lock-path=/var/run/nginx.lock       \
--with-ipv6                           \
--error-log-path=/var/log/nginx/error.log \
--http-log-path=/var/log/nginx/access.log \
--with-http_gzip_static_module        \
--with-http_stub_status_module        \
--with-http_ssl_module                \
--with-pcre                           \
--with-file-aio                       \
--without-http_uwsgi_module
make
make install
popd
rm -r /tmp/nginx-1.8.0*

## TODO: Configure nginx
#http://wiki.nginx.org/HttpScgiModule
#http://nginx.org/en/docs/http/ngx_http_scgi_module.html#example

#location /RPC2 {
#  include scgi_params;
#  scgi_pass localhost:5000;
#}

mkdir -p /var/www
chown www-data:www-data /var/www
addgroup nginx www-data

## Star nginx on restart
#wget -O /etc/init.d/nginx https://gist.github.com/sairam/5892520/raw/b8195a71e944d46271c8a49f2717f70bcd04bf1a/etc-init.d-nginx

#  nginx path prefix: "/etc/nginx"
#  nginx binary file: "/usr/sbin/nginx"
#  nginx configuration prefix: "/etc/nginx"
#  nginx configuration file: "/etc/nginx/nginx.conf"
#  nginx pid file: "/var/run/nginx.pid"
#  nginx error log file: "/var/log/nginx/error.log"
#  nginx http access log file: "/var/log/nginx/access.log"
#  nginx http client request body temporary files: "client_body_temp"
#  nginx http proxy temporary files: "proxy_temp"
#  nginx http scgi temporary files: "scgi_temp"

cat <<'EOF' > /etc/init.d/nginx
#! /bin/sh
 
### BEGIN INIT INFO
# Provides:          nginx
# Required-Start:    $all
# Required-Stop:     $all
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: starts the nginx web server
# Description:       starts nginx using start-stop-daemon
### END INIT INFO
 
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
DAEMON=/usr/sbin/nginx
NAME=nginx
DESC=nginx
 
test -x $DAEMON || exit 0
 
# Include nginx defaults if available
if [ -f /etc/default/nginx ] ; then
    . /etc/default/nginx
fi
 
set -e
 
. /lib/lsb/init-functions
 
case "$1" in
  start)
    echo -n "Starting $DESC: "
    start-stop-daemon --start --quiet --pidfile /var/run/$NAME.pid \
        --exec $DAEMON -- $DAEMON_OPTS || true
    echo "$NAME."
    ;;
  stop)
    echo -n "Stopping $DESC: "
    start-stop-daemon --stop --quiet --pidfile /var/run/$NAME.pid \
        --exec $DAEMON || true
    echo "$NAME."
    ;;
  restart|force-reload)
    echo -n "Restarting $DESC: "
    start-stop-daemon --stop --quiet --pidfile \
        /var/run/$NAME.pid --exec $DAEMON || true
    sleep 1
    start-stop-daemon --start --quiet --pidfile \
        /var/run/$NAME.pid --exec $DAEMON -- $DAEMON_OPTS || true
    echo "$NAME."
    ;;
  reload)
      echo -n "Reloading $DESC configuration: "
      start-stop-daemon --stop --signal HUP --quiet --pidfile /var/run/$NAME.pid \
          --exec $DAEMON || true
      echo "$NAME."
      ;;
  status)
      status_of_proc -p /var/run/$NAME.pid "$DAEMON" nginx && exit 0 || exit $?
      ;;
  *)
    N=/etc/init.d/$NAME
    echo "Usage: $N {start|stop|restart|reload|force-reload|status}" >&2
    exit 1
    ;;
esac
 
exit 0
EOF

chmod +x /etc/init.d/nginx
update-rc.d nginx defaults 99

echo "fastcgi_buffer_size 128k;" >>/etc/nginx/fastcgi.conf
echo "fastcgi_buffers 4 256k;" >>/etc/nginx/fastcgi.conf
echo "fastcgi_busy_buffers_size 256k;" >>/etc/nginx/fastcgi.conf


service nginx start

#TODO: IPTABLES

#rutorrent
#TODO: Configure it
wget https://github.com/Novik/ruTorrent/archive/master.zip
unzip master.zip
mv ruTorrent-master /var/www/rutorrent
chown www-data:www-data -R /var/www/rutorrent
rm master.zip
