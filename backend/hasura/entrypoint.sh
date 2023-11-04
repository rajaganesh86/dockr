#!/bin/sh

set -e

log() {
    TIMESTAMP=$(date -u "+%Y-%m-%dT%H:%M:%S.000+0000")
    MESSAGE=$1
    echo "{\"timestamp\":\"$TIMESTAMP\",\"level\":\"info\",\"type\":\"startup\",\"detail\":{\"kind\":\"migration-apply\",\"info\":\"$MESSAGE\"}}"
}

# wait for a port to be ready
wait_for_port() {
    local PORT=$1
    log "Waiting 30 seconds for $PORT to be ready"
    for i in `seq 1 30`;
    do
        nc localhost $PORT > /dev/null 2>&1 && log "Port $PORT is ready!!!" && return
        sleep 1
    done
    log "Failed waiting for $PORT." && exit 1
}
# Update Hasura CLI
hasura update-cli

log "Starting graphql engine temporarily"
graphql-engine serve &
PID=$!
wait_for_port 8080

# Apply existing Hasura migrations and metadata
cd /hasura
hasura metadata apply
hasura migrate apply --database-name pg

# kill graphql engine that we started earlier
log "killing temporary server"
kill $PID

# Start the Hasura GraphQL service
log "Graphql-engine will now start in normal mode"
exec graphql-engine serve
