#!/bin/bash
#
# Renders a foo.cfg.tpl file into foo.cfg
# Uses DNS RR resolution to render a line for each resolved host.
#
#   $ render_cfg.sh <hostnames> </path/to/some.cfg.tpl> [ip_address,...]
#
# Multiple hostnames may be given separated by commas, with no spaces

set -e

service=$1
template=$2

# Check for fatal errors
if ! [ -f $template ]; then
  echo "Template file $template does not exist."
  exit 1
fi

# Third parameter is list of ips
if [[ -n $3 ]]; then
  ips=(${3//,/ })

# Otherwise use DNS lookup
else
  oldfile=/tmp/cfg.$(<<<$service md5sum - | awk '{print $1}')
  tmpfile=$(mktemp -t cfg.XXXXXXX)

  # Resolve DNS
  for _service in ${service//,/ }; do
    nslookup $_service 2>/dev/null | awk '/^Name:/{p=1} p&&/^Address:/{ print $2 }'
  done | sort | paste -sd ',' > $tmpfile
  if [ $(wc -c $tmpfile | gawk '{print $1}') -eq 0 ]; then
    rm $tmpfile
    echo "Unable to resolve addresses for $service "
    exit 1
  fi

  # Check if IP addresses for service changed
  if test -f $oldfile && cmp -s $oldfile $tmpfile; then
    rm $tmpfile
    exit 2
  fi

  # Remove oldfile to prevent tmp file accumulation
  if [ -f $oldfile ]; then
    rm $oldfile
  fi

  echo "New service addresses: $(cat $tmpfile)"
  IFS=',' read -ra ips < $tmpfile
fi

tmptpl=$(mktemp -t tpl.XXXXXXX)
tmptpl2=$(mktemp -t tpl.XXXXXXX)
cp $template $tmptpl
index=0
while true; do
  pattern=$(sed -n '/^\s*{{HOSTS}}$/,/^\s*{{\/HOSTS}}$/{//!p}' $tmptpl | head -n 1)
  pattern=$(gawk '/^\s*{{\/HOSTS}}/{exit} p; /^\s*{{HOSTS}}$/{p=1} /^\s*{{\/HOSTS}}/{exit}' $tmptpl)
  #pattern='server ${service}${num} ${ip}:3306 check'
  [ -n "$pattern" ] || break
  gawk "BEGIN{a=0} /^\\s*{{HOSTS}}\$/&&a==0 {f=1} !f; /^\\s*{{\\/HOSTS}}\$/&&a==0 {print \"\${HOSTS$index}\"; f=0; a++}" $tmptpl > $tmptpl2
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
while true; do
  pattern=$(sed -n 's/.*{{HOSTS}}\(.*\){{\/HOSTS}}.*/\1/p' $tmptpl | head -n 1)
  [[ -n $pattern ]] || break
  gawk "!x{x=sub(/{{HOSTS}}.*{{\\/HOSTS}}/,\"\${HOSTS$index}\");} 1" < $tmptpl > $tmptpl2
  _SEP="${pattern: -1}"
  pattern="${pattern%?}"
  HOSTS="";SEP=""
  for ip in "${ips[@]}"; do
    num=${ip##*.}
    host=$(eval "echo \"$pattern\"")
    HOSTS=$(printf "$HOSTS$SEP$host")
    SEP=$_SEP
  done
  eval "HOSTS$index=\"$(printf "$HOSTS")\""
  index=$(($index + 1))
  cp $tmptpl2 $tmptpl
done
sed -i 's/\$/@@@/g' $tmptpl2
sed -i 's/@@@{HOSTS\([0-9]*\)}/${HOSTS\1}/g' $tmptpl2
eval "echo \"$(cat $tmptpl2)\"" > $tmptpl
sed -i 's/@@@/$/g' $tmptpl
mv $tmptpl ${template%.tpl}
rm $tmptpl2

# Update last DNS resolution result
if [[ -z $3 ]]; then
  mv $tmpfile $oldfile
fi

# 0 means config was updated
exit 0
