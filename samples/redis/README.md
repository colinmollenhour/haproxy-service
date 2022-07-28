Simply run `docker-compose up` in this directory to start two Redis instances and one HAProxy instance.

Stop one of the Redis instances (e.g. `docker stop redis-cache-1`) and observe that the HAProxy configuration is updated accordingly.
