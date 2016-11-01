#!/bin/bash -ex

# first arg is `-f` or `--some-option`
if [ "${1#-}" != "$1" ]; then
	set -- haproxy "$@"
fi

if [ "$1" = 'haproxy' ]; then
	# if the user wants "haproxy", let's use "haproxy-systemd-wrapper" instead so we can have proper reloadability implemented by upstream
	shift # "haproxy"
	set -- "$(which haproxy-systemd-wrapper)" -p /run/haproxy.pid "$@"
fi

# start processes
set +e -m

TEMPLATE=${TEMPLATE:-/etc/haproxy.cfg.tpl}
UPDATE_FREQUENCY=${UPDATE_FREQUENCY:-30}
if [ -z "$SERVICE_HOSTNAME" ]; then
	echo "The SERVICE_HOSTNAME environment variable is not defined."
	exit 1
fi

# Trap Shutdown
function shutdown () {
	echo Shutting down
	test -s /run/haproxy.pid && kill -TERM $(cat /run/haproxy.pid)
}
trap shutdown TERM INT

# Trap Reload (HUP)
function reload () {
    echo Reloading config
    test -s /run/haproxy.pid && kill -HUP $(cat /run/haproxy.pid)
}
trap reload HUP

# Render config template once before starting HAProxy
/render_cfg.sh $SERVICE_HOSTNAME $TEMPLATE
if [ $? -eq 1 ]; then
	sleep 5
	/render_cfg.sh $SERVICE_HOSTNAME $TEMPLATE
	if [ $? -eq 1 ]; then
    	echo "Could not render haproxy.cfg from template. Refusing to start."
		exit 1
	fi
fi

# Run loop to update config template
while sleep $UPDATE_FREQUENCY; do
	/render_cfg.sh $SERVICE_HOSTNAME $TEMPLATE
	# Exit code 0 means template was updated, 1 means error and 2 means not updated
    RENDER_RESULT=$?
	if [ $RENDER_RESULT -eq 0 ]; then
        reload
	elif [ $RENDER_RESULT -eq 1 ]; then
		echo "Error updating config template"
	fi
done &
renderPid=$!

# Run HAProxy and wait for exit
"$@" &
wait $!
RC=$?

kill $renderPid
exit $RC
