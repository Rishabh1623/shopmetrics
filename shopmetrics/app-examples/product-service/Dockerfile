FROM golang:1.21-alpine AS builder

WORKDIR /app

# Copy all files
COPY . .

# Download dependencies and build
RUN go mod download && \
    CGO_ENABLED=0 GOOS=linux go build -o product-service .

# Final stage
FROM alpine:latest

RUN apk --no-cache add ca-certificates

WORKDIR /root/

# Copy binary from builder
COPY --from=builder /app/product-service .

# Expose port
EXPOSE 8081

# Run the application
CMD ["./product-service"]
