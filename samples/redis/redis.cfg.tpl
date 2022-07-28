global
  log stderr format short daemon err

defaults
  mode tcp
  log global
  timeout client     1h
  timeout server     1h
  timeout connect 1000

frontend redis-tcp
  bind *:6379
  option tcplog
  default_backend redis

# The tcp-check will ensure that only reachable master nodes are considered up.
backend redis
  balance first
  option tcp-check
  tcp-check send PING\r\n
  tcp-check expect string +PONG
  tcp-check send info\ replication\r\n
  tcp-check expect string role:master
  tcp-check send info\ persistence\r\n
  tcp-check expect string loading:0
  tcp-check send QUIT\r\n
  tcp-check expect string +OK
  default-server inter 1000 downinter 2000 fastinter 500 rise 2 fall 3 maxconn 256 maxqueue 128
  {{HOSTS}}
  server node${num} ${ip}:6379 check
  {{/HOSTS}}

