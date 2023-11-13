# Use the official Hasura GraphQL Engine Docker image as the base image
FROM hasura/graphql-engine:v2.33.0.cli-migrations-v3

RUN mkdir -p /hasura-migrations
RUN mkdir -p /hasura-metadata

# Copy your migration and metadata files into the container
COPY metadata /hasura-metadata
COPY migrations /hasura-migrations
COPY config.yaml ./
EXPOSE 8080
