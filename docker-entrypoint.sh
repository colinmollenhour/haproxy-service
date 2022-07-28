#!/bin/bash

set -e

# first arg is `-f` or `--some-option`
if [ "${1#-}" != "$1" ]; then
	set -- haproxy "$@"
fi

KILLSIGNAL=HUP
PREFIX=docker-entrypoint.sh
TEMPLATE=${TEMPLATE:-/etc/haproxy.cfg.tpl}
UPDATE_FREQUENCY=${UPDATE_FREQUENCY:-10}

if [ "$1" = 'haproxy' ]; then
	shift # "haproxy"
	# if the user wants "haproxy", let's add a couple useful flags
	#   -W  -- "master-worker mode" (allows for reload via "SIGUSR2")
	set -- haproxy -W "$@"
fi


# enable job control, start processes
set -m

# Set 'TRACE=y' environment variable to see detailed output for debugging
[ "$TRACE" = "y" ] && set -x

if [ -z "$SERVICE_HOSTNAME" ]; then
	echo $PREFIX: The SERVICE_HOSTNAME environment variable is not defined.
	exit 1
fi

# Run init script if it exists
if [[ -f /docker-entrypoint-init.sh ]]; then
	source /docker-entrypoint-init.sh
fi

# Render config template once before starting HAProxy
/render_cfg.sh $SERVICE_HOSTNAME $TEMPLATE || RENDER_CODE=$?
if [[ $RENDER_CODE -eq 1 ]]; then
	sleep 5
	/render_cfg.sh $SERVICE_HOSTNAME $TEMPLATE || RENDER_CODE=$?
	if [[ $RENDER_CODE -eq 1 ]]; then
		echo "$PREFIX: Could not render ${TEMPLATE%.tpl}. Refusing to start. ($RENDER_CODE)"
		exit 1
	fi
fi

# Run HAProxy (haproxy-systemd-wrapper) and wait for exit
"$@" &
HAPROXY_PID=$!

# Trap Shutdown
function shutdown () {
	echo $PREFIX: Shutting down...
	kill -USR1 $HAPROXY_PID
}
trap shutdown TERM INT USR1

# Trap Reload (HUP or USR2)
function reload () {
	if haproxy -c -f ${TEMPLATE%.tpl} >/dev/null; then
		echo $PREFIX: Reloading config...
		kill -$KILLSIGNAL $HAPROXY_PID
	else
		echo $PREFIX: Config test failed, will not reload haproxy.
	fi
}
trap reload HUP USR2

# Run loop to update config template
while sleep $UPDATE_FREQUENCY; do
	/render_cfg.sh $SERVICE_HOSTNAME $TEMPLATE || RENDER_RESULT=$?
	# Exit code 0 means template was updated, 1 means error and 2 means not updated
	RENDER_RESULT=$?
	if [[ $RENDER_RESULT -eq 0 ]]; then
		reload
	elif [[ $RENDER_RESULT -eq 1 ]]; then
		echo "$PREFIX: Error updating config template! ($RENDER_RESULT)"
	fi
done &
RENDER_PID=$!

wait $HAPROXY_PID
RC=$?

kill $RENDER_PID
exit $RC
