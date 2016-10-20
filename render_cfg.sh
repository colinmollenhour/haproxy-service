#!/bin/bash
#
# Renders a foo.cfg.tpl file into foo.cfg
# Uses DNS RR resolution to render a line for each resolved host.
#
# $ render_cfg.sh <hostname> </path/to/haproxy.cfg.tpl>
#
service=$1
template=$2
oldfile=/tmp/cfg.$service
tmpfile=$(mktemp -t cfg.$service.XXXXXXX)
getent hosts $service | awk '{print $1}' | sort | paste -sd ',' > $tmpfile
#echo '1.2.3.4,1.2.3.5,1.2.3.6' > $tmpfile

# Check for fatal errors
if ! [ -f $template ]; then
  echo "Template file $template does not exist."
  exit 1
fi
if [ `wc -c $tmpfile | awk '{print $1}'` -eq 0 ]; then
  echo "Unable to resolve addresses for $service "
  exit 1
fi

# Check if IP addresses for service changed
if test -f $oldfile && cmp --silent $oldfile $tmpfile; then
  exit 2
fi

prefix=node
IFS=',' read -ra ips < $tmpfile
tmptpl=$(mktemp -t tpl.XXXXXXX)
tmptpl2=$(mktemp -t tpl.XXXXXXX)
cp $template $tmptpl
index=0
while true; do
  pattern=$(sed -n '/^\s*{{HOSTS}}$/,/^\s*{{\/HOSTS}}$/{//!p}' $tmptpl | head -n 1)
  #pattern='server ${service}${num} ${ip}:3306 check'
  [ -n "$pattern" ] || break
  awk "BEGIN{a=0} /{{HOSTS}}/&&a==0 {f=1} !f; /{{\\/HOSTS}}/&&a==0 {print \"\${HOSTS$index}\"; f=0; a++}" $tmptpl > $tmptpl2
  HOSTS="";SEP=""
  for ip in "${ips[@]}"; do
    num=${ip##*.}
    host=$(eval "echo \"$pattern\"")
    HOSTS=$(printf "$HOSTS$SEP$host")
    SEP=$'\n'
  done
  eval "HOSTS$index=\"$(printf "$HOSTS")\""
  index=$(($index + 1))
  cp $tmptpl2 $tmptpl
done
eval "echo \"$(cat $tmptpl2)\"" > $tmptpl
mv $tmptpl ${template%.tpl}
mv $tmpfile $oldfile
rm $tmptpl2

# 0 means config was updated
exit 0
