FROM golang:1.21-alpine AS builder

WORKDIR /app

# Install git (required for go mod)
RUN apk add --no-cache git

# Copy go mod files
COPY go.mod go.sum* ./

# Download dependencies
RUN go mod download

# Copy source code
COPY . .

# Build
RUN CGO_ENABLED=0 GOOS=linux go build -o product-service .

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
