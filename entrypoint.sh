#!/bin/sh
set -e

# Graceful shutdown: kill both processes
shutdown() {
    kill "$GOCLAW_PID" 2>/dev/null
    kill "$NGINX_PID" 2>/dev/null
    wait "$GOCLAW_PID" "$NGINX_PID" 2>/dev/null
    exit 0
}

case "${1:-serve}" in
    serve)
        # Managed mode: auto-upgrade (schema migrations + data hooks) before starting
        if [ "$GOCLAW_MODE" = "managed" ] && [ -n "$GOCLAW_POSTGRES_DSN" ]; then
            echo "Managed mode: running upgrade..."
            /app/goclaw upgrade || \
                echo "Upgrade warning (may already be up-to-date)"
        fi

        # Prepare nginx writable dirs under /tmp (read-only filesystem)
        mkdir -p /tmp/nginx/client_body /tmp/nginx/proxy /tmp/nginx/fastcgi \
                 /tmp/nginx/uwsgi /tmp/nginx/scgi /tmp/nginx/logs /tmp/nginx/run

        # Start goclaw in background
        /app/goclaw &
        GOCLAW_PID=$!

        # Start nginx (writable paths configured in nginx-main.conf → /tmp/nginx/)
        nginx -e /tmp/nginx/error.log -g 'daemon off;' &
        NGINX_PID=$!

        trap shutdown SIGTERM SIGINT

        # Exit when either process dies
        while kill -0 "$GOCLAW_PID" 2>/dev/null && kill -0 "$NGINX_PID" 2>/dev/null; do
            sleep 1
        done
        shutdown
        ;;
    upgrade)
        shift
        exec /app/goclaw upgrade "$@"
        ;;
    migrate)
        shift
        exec /app/goclaw migrate "$@"
        ;;
    onboard)
        exec /app/goclaw onboard
        ;;
    version)
        exec /app/goclaw version
        ;;
    *)
        # Pass through any other command to goclaw
        exec /app/goclaw "$@"
        ;;
esac
