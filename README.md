# Telemedicine Video Platform

Embeddable telemedicine video consultation API — patients and nurses/doctors connect via video, audio, and chat. Any existing app can integrate this as a service.

## Architecture

```
┌──────────────────────────────────────────────────────┐
│                  Client Applications                  │
│   JS Widget  │  React SDK  │  Direct API consumers   │
└──────────────────────┬───────────────────────────────┘
                       │
┌──────────────────────▼───────────────────────────────┐
│               API Gateway (Go)                        │
│  REST API · JWT Auth · Rate Limiting · CORS           │
└──────────────────────┬───────────────────────────────┘
                       │ gRPC
┌──────────────────────▼───────────────────────────────┐
│             Session Service (Go)                      │
│  Rooms · Queue · Participants · Chat · LiveKit SDK    │
└──────────┬───────────────────────────┬───────────────┘
           │                           │
    ┌──────▼──────┐             ┌──────▼──────┐
    │   LiveKit   │             │  PostgreSQL  │
    │  SFU Server │             │  + Redis     │
    └─────────────┘             └──────────────┘
```

## Services

| Service | Description | Repo |
|---------|-------------|------|
| **shared** | Protobuf, domain models, middleware | [shared](https://github.com/tele-medic/shared) |
| **session-service** | Core session/room/queue management | [session-service](https://github.com/tele-medic/session-service) |
| **api-gateway** | Public REST API, authentication | [api-gateway](https://github.com/tele-medic/api-gateway) |
| **turn-server** | STUN/TURN relay (Pion) | [turn-server](https://github.com/tele-medic/turn-server) |
| **webhook-service** | Outbound webhook delivery | [webhook-service](https://github.com/tele-medic/webhook-service) |
| **recording-service** | Call recording via LiveKit Egress | [recording-service](https://github.com/tele-medic/recording-service) |
| **notification-service** | WebSocket, push, email, SMS | [notification-service](https://github.com/tele-medic/notification-service) |
| **web-sdk** | Embeddable TypeScript SDK/widget | [web-sdk](https://github.com/tele-medic/web-sdk) |

## Quick Start

```bash
# Clone with all submodules
git clone --recurse-submodules git@github.com:tele-medic/telemedicine.git
cd telemedicine

# Start all infrastructure + services
docker compose up -d

# Verify
curl http://localhost:8080/health
```

## Tech Stack

- **Go** — API Gateway, Session Service, TURN Server, Webhook, Recording, Notifications
- **TypeScript** — Web SDK / embeddable widget
- **LiveKit** — WebRTC SFU (built on Pion)
- **PostgreSQL** — persistent storage
- **Redis** — pub/sub events, caching, LiveKit coordination
- **MinIO** — S3-compatible recording storage (dev)

## Development

```bash
make init     # Initialize submodules
make build    # Build all Docker images
make up       # Start everything
make logs     # View logs
make test     # Run tests
make down     # Stop everything
```
