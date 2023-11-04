#!/bin/sh

# Make sure the Hasura CLI is up-to-date
hasura update-cli

# Apply existing Hasura migrations and metadata
hasura migrate apply --database-name pg
hasura metadata apply --database-name pg

# Start the Hasura GraphQL service
exec graphql-engine serve
