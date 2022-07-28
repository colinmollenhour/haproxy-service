# HAProxy Service Load Balancer

This container updates an HAProxy config template periodically using the results of DNS resolution
to trigger the update and apply the template and reload HAProxy.

## Usage

You can either run this container directly by mounting a template file at /etc/haproxy.cfg.tpl
or by copying and baking the template file in using a new Dockerfile. Either way it requires
an environment variable `SERVICE_HOSTNAME` which is the DNS name to resolve when updating the template.
Multiple DNS hostnames may be specified separated by commas.

#### Logging

HAProxy 1.9+ supports direct to stdout/stderr logging so rsyslog was removed.

#### User

This container runs as `root` rather than `haproxy` as it must write over the config file while running.

#### Usage

Run the image directly by mounting the config file as a volume:

    $ docker run \
      -e SERVICE_HOSTNAME=tasks.galera \
      -e UPDATE_FREQUENCY=10 \
      -v /path/to/your/haproxy.cfg.tpl:/etc/haproxy.cfg.tpl:ro \
      colinmollenhour/haproxy-service:2.6-alpine

Or build the config into the image:

    FROM colinmollenhour/haproxy-service:2.6-alpine
    COPY haproxy.cfg.tpl /etc/haproxy.cfg.tpl
    ENV SERVICE_HOSTNAME my-service
    ENV UPDATE_FREQUENCY 5

See the `samples/` directory for basic examples.

#### Template Format

Any block of text between the markers `{{HOSTS}}` and `{{/HOSTS}}` (must be on separate lines) will be rendered
in-place for each IP resolved by the `SERVICE_HOSTNAME`. The variables `$ip` and `$num` (the last octet of the `$ip`)
will be replaced accordingly. The IP addresses will always be sorted in the same order.
There may be multiple `{{HOSTS}} ... {{/HOSTS}}` blocks in the same template file.

Example:

    default-server inter 1s
    {{HOSTS}}
    server node${num} ${ip}:3306 check
    {{/HOSTS}}

If the `SERVICE_HOSTNAME` resolves to 10.0.0.12 and 10.0.0.20 it would render:

    default-server inter 1s
    server node12 10.0.0.12:3306 check
    server node20 10.0.0.20:3306 check

#### Init Scripts

If you need to run some basic scripts on init before the first template render mount or add a file at
`/docker-entrypoint-init.sh` which will be sourced by `docker-entrypoint.sh` once on startup.

