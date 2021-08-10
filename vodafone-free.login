#!/bin/sh
# captive portal auto-login script for vodafone hotspots in free mode (DE)
# Copyright (c) 2021 Andrijan Moecker (amo@ct.de)
# This is free software, licensed under the GNU General Public License v3.

# set (s)hellcheck exceptions
# shellcheck disable=1091,3040

export LC_ALL=C
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"
set -o pipefail

# source function library if necessary
#
if [ -z "${_C}" ]; then
	. "/lib/functions.sh"
fi

trm_domain="hotspot.vodafone.de"
trm_useragent="$(uci_get travelmate global trm_useragent "Mozilla/5.0 (Linux x86_64; rv:90.0) Gecko/20100101 Firefox/90.0")"
trm_captiveurl="$(uci_get travelmate global trm_captiveurl "http://detectportal.firefox.com")"
trm_maxwait="$(uci_get travelmate global trm_maxwait "30")"
trm_fetch="$(command -v curl)"
trm_ssid ="Vodafone Hotspot"

getsid () {
	raw_html="$(${trm_fetch} --user-agent "${trm_useragent}" --referer "http://www.example.com" --connect-timeout $((trm_maxwait / 6)) --write-out "%{redirect_url}" --silent --show-error --output /dev/null "${trm_captiveurl}")"
	sid="$(printf "%s" "${raw_html}" 2>/dev/null | awk 'BEGIN{FS="[=&]"}{printf "%s",$2}')"
}

getsession () {
	raw_html="$("${trm_fetch}" --user-agent "${trm_useragent}" --referer "http://${trm_domain}/portal/?sid=${sid}" --silent --connect-timeout $((trm_maxwait / 6)) "https://${trm_domain}/api/v4/session?sid=${sid}")"
	session="$(printf "%s" "${raw_html}" 2>/dev/null | jsonfilter -q -l1 -e '@.session')"
}

loginrequest () {
	raw_html="$("${trm_fetch}" --user-agent "${trm_useragent}" --referer "http://${trm_domain}/portal/?sid=${sid}" --silent --connect-timeout $((trm_maxwait / 6)) --data "accessType=termsOnly&loginProfile=${loginProfile}&session=${session}" "https://${trm_domain}/api/v4/login?sid=${sid}")"
	success="$(printf "%s" "${raw_html}" 2>/dev/null | jsonfilter -q -l1 -e '@.success')"
}

connectioncheck () {
	if [/etc/init.d/tavelmate status | grep connected ] && [/etc/init.d/tavelmate status | grep "Vodafone Hotspot"]; then
		return 1
	else
		return 0
	fi
}

randomwifimac () {
	ucipath = uci show wireless | grep "Vodafone Hotspot" | sed 's/.ssid=.*//'
	randommac =$(dd if=/dev/urandom bs=1024 count=1 2>/dev/null | md5sum | sed -e 's/^\(..\)\(..\)\(..\)\(..\)\(..\)\(..\).*$/\1:\2:\3:\4:\5:\6/' -e 's/^\(.\)[13579bdf]/\10/')
	uci set $(ucipath).macddr=($randommac)
	uci commit wireless
	wifi
}

while :
do
	getsid
	getsession
	loginrequest
	sleep 29m
	if [connectioncheck = 1]; then
		randomwifimac
	else
		exit 0
	fi
done
