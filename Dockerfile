# Use the official Golang image as a build stage with Go 1.22
FROM golang:1.22-alpine AS builder

# Set the Current Working Directory inside the container
WORKDIR /app

# Copy go.mod and go.sum files
COPY go.mod go.sum ./

# Download all dependencies
RUN go mod download

# Copy the source code into the container
COPY . .

# Build the Go app
RUN go build -o /gcf-list-buckets

# Use a minimal image for the runtime
FROM alpine:3.18

# Add a non-root user for security
RUN adduser -D appuser

# Copy the binary from the builder stage
COPY --from=builder /gcf-list-buckets /gcf-list-buckets

# Change to the non-root user
USER appuser

# Expose port 8080 to the outside world
EXPOSE 8080

# Command to run the executable
ENTRYPOINT ["/gcf-list-buckets"]
