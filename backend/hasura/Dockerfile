# Use the official Hasura GraphQL Engine Docker image as the base image
FROM hasura/graphql-engine:latest

# Install Hasura CLI
RUN apt update
RUN curl -L https://github.com/hasura/graphql-engine/raw/stable/cli/get.sh | bash

# Create a directory for your migrations and metadata files
#RUN mkdir -p /hasura-migrations
#RUN mkdir -p /hasura-metadata

# Copy your migration and metadata files into the container
COPY migrations /migrations
COPY metadata /metadata
COPY config.yaml ./

# Copy the entrypoint script into the container
COPY entrypoint.sh ./

# Make the entrypoint script executable
RUN chmod +x ./entrypoint.sh
