# Build stage
FROM golang:1.22-alpine AS build
WORKDIR /app
COPY go.mod .
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /out/gateway

# Runtime stage
FROM gcr.io/distroless/base-debian12
WORKDIR /app
COPY --from=build /out/gateway /usr/local/bin/gateway
EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/usr/local/bin/gateway"]
