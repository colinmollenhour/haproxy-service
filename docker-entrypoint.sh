#!/bin/bash

# first arg is `-f` or `--some-option`
if [ "${1#-}" != "$1" ]; then
	set -- haproxy "$@"
fi

if [ "$1" = 'haproxy' ]; then
	# if the user wants "haproxy", let's use "haproxy-systemd-wrapper" instead so we can have proper reloadability implemented by upstream
	shift # "haproxy"
	set -- "$(which haproxy-systemd-wrapper)" -p /run/haproxy.pid "$@"
fi

PREFIX=docker-entrypoint.sh
TEMPLATE=${TEMPLATE:-/etc/haproxy.cfg.tpl}
UPDATE_FREQUENCY=${UPDATE_FREQUENCY:-30}

# enable job control, start processes
set -m

# Set 'TRACE=y' environment variable to see detailed output for debugging
[ "$TRACE" = "y" ] && set -x

if [ -z "$SERVICE_HOSTNAME" ]; then
	echo $PREFIX: The SERVICE_HOSTNAME environment variable is not defined.
	exit 1
fi

# Render config template once before starting HAProxy
/render_cfg.sh $SERVICE_HOSTNAME $TEMPLATE
if [ $? -eq 1 ]; then
	sleep 5
	/render_cfg.sh $SERVICE_HOSTNAME $TEMPLATE
	if [ $? -eq 1 ]; then
		echo $PREFIX: Could not render ${TEMPLATE%.tpl}. Refusing to start.
		exit 1
	fi
fi

# Run rsyslogd if enabled
RSYSLOG_PID=0
if [ "$RSYSLOG" != "n" ]; then
	rsyslogd -n -f /etc/rsyslogd.conf &
	RSYSLOGD_PID=$!
fi

# Run HAProxy (haproxy-systemd-wrapper) and wait for exit
"$@" &
WRAPPER_PID=$!

# Trap Shutdown
function shutdown () {
	echo $PREFIX: Shutting down...
	kill -TERM $WRAPPER_PID
}
trap shutdown TERM INT

# Trap Reload (HUP)
function reload () {
	if haproxy -c -f ${TEMPLATE%.tpl} >/dev/null; then
		echo $PREFIX: Reloading config...
		kill -HUP $WRAPPER_PID
	else
		echo $PREFIX: Config test failed, will not reload haproxy.
	fi
}
trap reload HUP

# Run loop to update config template
while sleep $UPDATE_FREQUENCY; do
	/render_cfg.sh $SERVICE_HOSTNAME $TEMPLATE
	# Exit code 0 means template was updated, 1 means error and 2 means not updated
	RENDER_RESULT=$?
	if [ $RENDER_RESULT -eq 0 ]; then
		reload
	elif [ $RENDER_RESULT -eq 1 ]; then
		echo $PREFIX: Error updating config template!
	fi
done &
RENDER_PID=$!

wait $WRAPPER_PID
RC=$?

kill $RENDER_PID
[ "$RSYSLOG_PID" -ne 0 ] && kill $RSYSLOG_PID
exit $RC
