# Telemedicine Video Platform — Deep Research & Architecture Document

## Table of Contents
1. [Existing Projects Worldwide](#1-existing-projects-worldwide)
2. [Technology Deep Dive](#2-technology-deep-dive)
3. [Service Architecture](#3-service-architecture)
4. [Git Submodule Strategy](#4-git-submodule-strategy)
5. [Design Patterns & Code Architecture](#5-design-patterns--code-architecture)
6. [Database Schemas](#6-database-schemas)
7. [API Design](#7-api-design)
8. [Infrastructure](#8-infrastructure)
9. [Implementation Plan](#9-implementation-plan)

---

## 1. Existing Projects Worldwide

### 1.1 Open-Source Telemedicine Platforms

| Project | Tech Stack | Features | Stars | Status |
|---------|-----------|----------|-------|--------|
| **OpenMRS + Telehealth Module** | Java/Spring | EHR + video integration, mostly Jitsi-based | 1.5k+ | Active, modular |
| **Jitsi Meet** | Java (backend) + React | Full video conferencing, used by healthcare orgs as base | 23k+ | Very active |
| **BigBlueButton** | Java/Scala + React | Education-focused, adapted for telehealth group sessions | 8k+ | Active |
| **EasyRTC** | Node.js | Simple WebRTC signaling + example apps | 2k+ | Maintenance mode |
| **mediasoup** | Node.js (C++ core) | SFU library, used by healthcare startups | 6k+ | Active |
| **LiveKit** | Go (Pion-based) | Full SFU + SDKs + recording, healthcare adopters | 12k+ | Very active |
| **Dyte** | Proprietary + SDK | Embeddable video SDK, healthcare vertical | N/A | Commercial |
| **OpenVidu** | Java/Kurento | WebRTC platform with recording, used in telehealth | 3k+ | Active |

### 1.2 Commercial Embeddable Video APIs

#### Daily.co
- **Model**: Embeddable iframe or JS SDK
- **Auth**: API keys + meeting tokens (JWT)
- **API Pattern**: REST API for rooms → generate token → client joins with token
- **Healthcare**: HIPAA-compliant tier, BAA available
- **Key insight**: Rooms are ephemeral or persistent. Token carries permissions (can_publish, can_subscribe, user_name)
- **Pricing**: Per-participant-minute

#### Twilio Video
- **Model**: JS/iOS/Android SDKs, no iframe
- **Auth**: Account SID + Auth Token → generate Access Token (JWT) with Video Grant
- **API Pattern**: Create Room via REST → generate token with room grant → client connects
- **Healthcare**: HIPAA eligible, peer-to-peer or group rooms (SFU)
- **Key insight**: Composition API for recording, webhooks for room events
- **Pricing**: Per-participant-minute, separate recording charges

#### Vonage (TokBox) Video API
- **Model**: JS/iOS/Android SDKs
- **Auth**: API Key + Secret → generate session → generate token
- **API Pattern**: Create Session → Create Token → Client connects
- **Healthcare**: HIPAA compliant, archiving/recording built-in
- **Key insight**: Session = Room concept, Publisher/Subscriber model

#### Agora
- **Model**: Native SDKs (best for mobile), web SDK
- **Auth**: App ID + Token (RTC token with channel/uid/role)
- **Healthcare**: SOC2, used by Practo (Indian telehealth giant)
- **Key insight**: Channel-based model, cloud recording, real-time messaging SDK separate

#### Whereby Embedded
- **Model**: iframe-first (simplest integration)
- **Auth**: API key → create room → embed URL in iframe
- **Healthcare**: HIPAA compliant, built-in waiting room, knock-to-enter
- **Key insight**: Simplest integration model — just an iframe with a URL

### 1.3 Key Patterns Extracted from Commercial Platforms

```
Common API Flow (all platforms):
1. Server: Create room/session → returns room_id
2. Server: Generate token (JWT) with room_id + participant identity + permissions
3. Client: Connect to room using token
4. Server: Receive webhooks for events (participant joined/left, recording ready)
```

```
Common Auth Model:
- API Key + Secret (server-side, never exposed to client)
- Short-lived JWT tokens for clients (5min-24hr expiry)
- Token encodes: room, identity, permissions, expiry
- Webhook signatures for event verification
```

---

## 2. Technology Deep Dive

### 2.1 LiveKit — Our SFU Choice

**Architecture:**
```
┌─────────────────────────────────────────────────┐
│                LiveKit Server                    │
│  ┌───────────┐  ┌──────────┐  ┌──────────────┐ │
│  │ Signaling  │  │   SFU    │  │  Room Mgr    │ │
│  │ (WebSocket │  │ (Pion    │  │ (Participants│ │
│  │  + HTTP)   │  │  WebRTC) │  │  Tracks)     │ │
│  └───────────┘  └──────────┘  └──────────────┘ │
│  ┌───────────┐  ┌──────────┐  ┌──────────────┐ │
│  │ TURN      │  │ Codec    │  │  Quality     │ │
│  │ (built-in │  │ Support  │  │  Adaptation  │ │
│  │  or ext)  │  │ VP8/VP9  │  │  Simulcast   │ │
│  │           │  │ H264/AV1 │  │  Dynacast    │ │
│  └───────────┘  └──────────┘  └──────────────┘ │
│  ┌─────────────────────────────────────────────┐│
│  │        Redis (multi-node coordination)       ││
│  └─────────────────────────────────────────────┘│
└─────────────────────────────────────────────────┘
```

**Key Components:**
- **livekit-server**: Core SFU, handles WebRTC, rooms, participants, tracks
- **livekit-egress**: Recording service (composite/track recording, RTMP output, S3/GCS upload)
- **livekit-ingress**: Ingest from RTMP/WHIP sources into rooms
- **livekit-sip**: SIP/PSTN bridge for phone dial-in (future use)
- **Server SDKs**: Go, Node, Python, Ruby, PHP, Rust — for token generation, room management, webhooks

**Why LiveKit over Jitsi/mediasoup/OpenVidu:**
1. **Pure Go** — matches our stack, single binary, no JVM/C++ dependencies
2. **Built on Pion** — we understand the internals, can debug issues
3. **Client SDKs ready** — JS, React, React Native, iOS, Android, Flutter, Unity
4. **Egress** — built-in recording without custom ffmpeg pipelines
5. **Scalable** — Redis-coordinated multi-node, horizontal scaling
6. **Self-hostable** — Apache 2.0, no vendor lock-in
7. **Modern** — AV1 codec support, simulcast, dynacast, adaptive bitrate

**LiveKit Server SDK for Go — Key APIs:**
```go
// Room management
client.CreateRoom(ctx, &livekit.CreateRoomRequest{Name: "room-123"})
client.ListRooms(ctx, &livekit.ListRoomsRequest{})
client.DeleteRoom(ctx, &livekit.DeleteRoomRequest{Room: "room-123"})

// Participant management
client.ListParticipants(ctx, &livekit.ListParticipantsRequest{Room: "room-123"})
client.RemoveParticipant(ctx, &livekit.RoomParticipantIdentity{Room: "room-123", Identity: "user-1"})
client.MutePublishedTrack(ctx, &livekit.MuteRoomTrackRequest{...})

// Token generation
token := auth.NewAccessToken(apiKey, apiSecret)
grant := &auth.VideoGrant{
    RoomJoin: true,
    Room:     "room-123",
}
token.AddGrant(grant).SetIdentity("user-1").SetValidFor(time.Hour)
jwt, _ := token.ToJWT()

// Webhooks
webhookReceiver := webhook.NewURLVerifier(apiKey, apiSecret)
event, _ := webhookReceiver.Receive(req.Body, req.Header.Get("Authorization"))
// event.Event can be: "room_started", "room_finished", "participant_joined", etc.
```

### 2.2 Pion WebRTC — Understanding the Foundation

**Module dependency tree:**
```
pion/webrtc (core API)
├── pion/ice (ICE agent, candidate gathering, connectivity checks)
│   ├── pion/stun (STUN client/server)
│   ├── pion/turn (TURN client)
│   └── pion/mdns (mDNS for local discovery)
├── pion/dtls (DTLS 1.2 encryption for media)
├── pion/srtp (Secure RTP encryption/decryption)
├── pion/rtp (RTP packet parse/construct)
├── pion/rtcp (RTCP feedback: SR, RR, NACK, PLI, REMB, TWCC)
├── pion/sdp (SDP parse/serialize)
├── pion/sctp (SCTP for DataChannels)
├── pion/datachannel (DataChannel API over SCTP)
├── pion/interceptor (middleware for RTP/RTCP processing)
│   ├── NACK responder/generator (packet loss recovery)
│   ├── TWCC sender/receiver (transport-wide congestion control)
│   └── Stats interceptor (quality metrics)
└── pion/logging (structured logging)
```

**What LiveKit uses from Pion:**
- PeerConnection for each participant
- TrackLocal/TrackRemote for forwarding media between participants
- Interceptors for NACK, TWCC, bandwidth estimation
- DataChannels for real-time data (chat messages, reactions)
- ICE for connectivity

### 2.3 Pion TURN Server

We'll run our own TURN server using `pion/turn`:
- Pure Go, embeddable in our own binary or standalone
- Supports UDP, TCP, TLS, DTLS relay
- Long-term credential mechanism (username/password per session)
- Can generate ephemeral credentials (time-limited, HMAC-based)
- Critical for Uzbekistan where ~20-30% of users may be behind symmetric NAT

### 2.4 Supporting Go Libraries

| Library | Purpose | Why this one |
|---------|---------|-------------|
| `go-chi/chi` | HTTP router | Idiomatic, composable middleware, stdlib compatible |
| `coder/websocket` | WebSocket (was nhooyr.io/websocket) | Modern, context-aware, maintained by Coder |
| `golang-jwt/jwt` | JWT tokens | Industry standard for Go |
| `jackc/pgx` | PostgreSQL | Fastest Go PG driver, native types, pgxpool |
| `redis/go-redis` | Redis | Full-featured, Pub/Sub, pipeline, clustering |
| `golang-migrate/migrate` | DB migrations | SQL-based, no ORM required |
| `google/uuid` | UUIDs | Standard, well-tested |
| `go-playground/validator` | Struct validation | Tag-based, comprehensive |
| `rs/cors` | CORS middleware | Standard, works with Chi |
| `log/slog` | Structured logging | Go stdlib since 1.21 |
| `golang.org/x/crypto` | bcrypt, encryption | Official Go extended lib |
| `google/wire` | Dependency injection | Compile-time DI, no reflection |

---

## 3. Service Architecture

### 3.1 Service Decomposition

Based on analysis of LiveKit's architecture + commercial platforms + domain-driven design:

```
┌─────────────────────────────────────────────────────────────────────┐
│                         UMBRELLA REPO                               │
│                    telemedicine (git repo)                           │
│                                                                     │
│  ┌─────────────┐  ┌─────────────┐  ┌──────────────┐  ┌──────────┐ │
│  │  api-gateway │  │  session-   │  │  turn-server │  │  web-sdk │ │
│  │  (submodule) │  │  service    │  │  (submodule) │  │(submodule)│ │
│  │              │  │  (submodule)│  │              │  │           │ │
│  └──────┬───────┘  └──────┬──────┘  └──────┬───────┘  └─────┬────┘ │
│         │                 │                │                │      │
│  ┌──────┴───────┐  ┌──────┴──────┐  ┌──────┴───────┐             │
│  │  webhook-    │  │  recording- │  │  notification│             │
│  │  service     │  │  service    │  │  -service    │             │
│  │  (submodule) │  │  (submodule)│  │  (submodule) │             │
│  └──────────────┘  └─────────────┘  └──────────────┘             │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                     shared (submodule)                        │  │
│  │  proto/ │ models/ │ errors/ │ middleware/ │ config/           │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                     │
│  docker-compose.yml  │  Makefile  │  .gitmodules                   │
└─────────────────────────────────────────────────────────────────────┘
```

### 3.2 Service Responsibilities

#### Service 1: `api-gateway`
**Purpose**: Public-facing API, authentication, request routing
- REST API for tenant management (API keys, webhook URLs)
- REST API for session/room CRUD
- JWT token generation for clients
- Rate limiting, request validation
- Routes to internal services via gRPC
- WebSocket proxy for real-time signaling events

#### Service 2: `session-service`
**Purpose**: Core business logic — sessions, rooms, queue, participants
- Room lifecycle management (create, join, leave, end)
- Waiting room / queue system
- Participant state management
- LiveKit Server SDK integration (room creation, token generation)
- Session metadata (duration, participants, notes)
- gRPC server for internal communication

#### Service 3: `turn-server`
**Purpose**: NAT traversal TURN/STUN relay
- Pion TURN server with TLS support
- Ephemeral credential generation (HMAC-based, time-limited)
- Metrics export (active relays, bandwidth)
- Multiple listener support (UDP 3478, TCP 3478, TLS 5349)
- Can run as standalone or embedded

#### Service 4: `webhook-service`
**Purpose**: Reliable outbound webhook delivery
- Receives events from other services via Redis Pub/Sub or NATS
- Delivers webhooks to tenant endpoints with retry logic
- Exponential backoff with jitter (3 retries over 15 minutes)
- HMAC signature on payloads for verification
- Delivery logs and status tracking
- Dead letter queue for failed deliveries

#### Service 5: `recording-service`
**Purpose**: Call recording management
- Interfaces with LiveKit Egress for recording
- Consent management (both parties must consent)
- Storage management (S3-compatible: MinIO locally, S3/R2 in prod)
- Recording lifecycle (start, stop, process, store, expire)
- Post-processing (format conversion if needed)
- Signed URL generation for playback

#### Service 6: `notification-service`
**Purpose**: Real-time and async notifications
- WebSocket hub for real-time events to connected clients
- Push notification integration (FCM/APNs for mobile)
- Email notifications (appointment reminders, call summaries)
- SMS notifications (via SMS gateway — important for Uzbekistan market)
- Event fan-out from Redis Pub/Sub

#### Service 7: `web-sdk`
**Purpose**: Embeddable JavaScript SDK + widget
- TypeScript SDK wrapping LiveKit client SDK + our API
- Pre-built UI components (video tiles, controls, chat)
- Embeddable widget (single script tag or npm package)
- Pre-call device checker
- Responsive design (mobile-first for Uzbekistan users)

#### Service 8: `shared`
**Purpose**: Shared code across Go services
- Protobuf definitions for gRPC
- Common models (User, Session, Room, etc.)
- Error types and codes
- Middleware (auth, logging, recovery)
- Config loading utilities
- Database migration utilities

### 3.3 Inter-Service Communication

```
┌────────────┐     REST/WS      ┌──────────────┐
│   Client   │ ◄──────────────► │ API Gateway  │
│ (Browser/  │                  │              │
│  Mobile)   │                  └──────┬───────┘
└─────┬──────┘                         │ gRPC
      │                                │
      │ WebRTC                  ┌──────▼───────┐
      │                         │   Session    │
      │                         │   Service    │
      │                         └──────┬───────┘
      │                                │ gRPC + Redis Pub/Sub
      │                    ┌───────────┼───────────┐
      │                    │           │           │
      │             ┌──────▼──┐ ┌──────▼──┐ ┌─────▼─────┐
      │             │Webhook  │ │Recording│ │Notification│
      │             │Service  │ │Service  │ │Service     │
      │             └─────────┘ └─────────┘ └────────────┘
      │
      │ STUN/TURN          ┌──────────────┐
      └───────────────────►│ TURN Server  │
                           └──────────────┘

Communication patterns:
- Client ↔ API Gateway: REST (HTTPS) + WebSocket
- Client ↔ LiveKit: WebRTC (UDP/TCP via TURN)
- API Gateway → Session Service: gRPC (internal)
- Session Service → Others: Redis Pub/Sub (events)
- Webhook/Recording/Notification: consume events from Redis
```

**Why gRPC for internal:**
- Type-safe contracts (protobuf)
- Efficient binary serialization
- Streaming support for real-time data
- Built-in deadline/timeout propagation
- Code generation for Go

**Why Redis Pub/Sub for events:**
- Already required by LiveKit for multi-node coordination
- Low latency event delivery
- Simple to implement fan-out
- No additional infrastructure (vs. Kafka/RabbitMQ for MVP)

---

## 4. Git Submodule Strategy

### 4.1 Repository Structure

```
github.com/your-org/telemedicine          ← Umbrella repo (orchestration)
github.com/your-org/telemedicine-shared   ← Shared code (proto, models)
github.com/your-org/telemedicine-gateway  ← API Gateway service
github.com/your-org/telemedicine-session  ← Session service
github.com/your-org/telemedicine-turn     ← TURN server
github.com/your-org/telemedicine-webhook  ← Webhook delivery service
github.com/your-org/telemedicine-recording ← Recording service
github.com/your-org/telemedicine-notify   ← Notification service
github.com/your-org/telemedicine-web-sdk  ← JavaScript/TypeScript SDK
```

### 4.2 .gitmodules Configuration

```gitmodules
[submodule "shared"]
    path = shared
    url = ../telemedicine-shared.git

[submodule "services/gateway"]
    path = services/gateway
    url = ../telemedicine-gateway.git

[submodule "services/session"]
    path = services/session
    url = ../telemedicine-session.git

[submodule "services/turn"]
    path = services/turn
    url = ../telemedicine-turn.git

[submodule "services/webhook"]
    path = services/webhook
    url = ../telemedicine-webhook.git

[submodule "services/recording"]
    path = services/recording
    url = ../telemedicine-recording.git

[submodule "services/notify"]
    path = services/notify
    url = ../telemedicine-notify.git

[submodule "sdk/web"]
    path = sdk/web
    url = ../telemedicine-web-sdk.git
```

### 4.3 Why Submodules (Not Monorepo or Separate Repos)

| Approach | Pros | Cons |
|----------|------|------|
| **Monorepo** | Single clone, easy cross-service refactoring | CI/CD complexity, large repo, single versioning |
| **Separate repos** | Independent CI/CD, clear ownership | Hard to test cross-service, version drift |
| **Submodules** (chosen) | Independent CI/CD per service, single clone for full system, clear boundaries, each service has own go.mod | Requires understanding of git submodules, pinned commits need updating |

**Submodules give us:**
- Each service is independently deployable and versionable
- `docker-compose.yml` in umbrella repo can spin up everything
- Shared proto/models via `shared` submodule (referenced as Go module)
- CI/CD per service repo + integration tests in umbrella
- Easy for new developers: `git clone --recurse-submodules` gets everything

---

## 5. Design Patterns & Code Architecture

### 5.1 Per-Service Architecture Pattern: Clean Architecture

Each Go service follows the same internal structure:

```
service/
├── cmd/
│   └── server/
│       └── main.go                 # Wiring, startup, graceful shutdown
├── internal/
│   ├── domain/                     # Layer 1: Domain (innermost)
│   │   ├── models.go               #   Pure data types, no dependencies
│   │   ├── errors.go               #   Domain-specific errors
│   │   └── events.go               #   Domain events
│   ├── port/                       # Layer 2: Ports (interfaces)
│   │   ├── repository.go           #   Database interface
│   │   ├── publisher.go            #   Event publishing interface
│   │   └── external.go             #   External service interfaces
│   ├── service/                    # Layer 3: Application/Use Cases
│   │   ├── session_service.go      #   Business logic orchestration
│   │   └── session_service_test.go #   Unit tests with mocked ports
│   ├── adapter/                    # Layer 4: Adapters (outermost)
│   │   ├── postgres/               #   Implements repository port
│   │   │   ├── session_repo.go
│   │   │   └── migrations/
│   │   ├── redis/                  #   Implements publisher port
│   │   │   └── event_publisher.go
│   │   ├── livekit/                #   Implements LiveKit integration
│   │   │   └── room_client.go
│   │   ├── grpc/                   #   gRPC server handlers
│   │   │   └── session_handler.go
│   │   └── http/                   #   HTTP handlers (if needed)
│   │       ├── router.go
│   │       ├── middleware.go
│   │       └── handlers.go
│   └── config/
│       └── config.go               # Service configuration
├── go.mod
├── go.sum
├── Dockerfile
└── Makefile
```

### 5.2 Key Design Patterns Used

#### Repository Pattern
```go
// port/repository.go — interface defined in ports
type SessionRepository interface {
    Create(ctx context.Context, session *domain.Session) error
    GetByID(ctx context.Context, id uuid.UUID) (*domain.Session, error)
    UpdateStatus(ctx context.Context, id uuid.UUID, status domain.SessionStatus) error
    ListByTenant(ctx context.Context, tenantID uuid.UUID, filter ListFilter) ([]domain.Session, error)
}

// adapter/postgres/session_repo.go — implementation
type sessionRepo struct {
    pool *pgxpool.Pool
}

func (r *sessionRepo) Create(ctx context.Context, session *domain.Session) error {
    _, err := r.pool.Exec(ctx,
        `INSERT INTO sessions (id, tenant_id, room_name, status, created_at)
         VALUES ($1, $2, $3, $4, $5)`,
        session.ID, session.TenantID, session.RoomName, session.Status, session.CreatedAt,
    )
    return err
}
```

#### Event-Driven Pattern
```go
// port/publisher.go
type EventPublisher interface {
    Publish(ctx context.Context, event domain.Event) error
}

// domain/events.go
type Event struct {
    Type      EventType
    TenantID  uuid.UUID
    SessionID uuid.UUID
    Payload   any
    Timestamp time.Time
}

type EventType string
const (
    EventSessionCreated      EventType = "session.created"
    EventParticipantJoined   EventType = "participant.joined"
    EventParticipantLeft     EventType = "participant.left"
    EventSessionEnded        EventType = "session.ended"
    EventRecordingStarted    EventType = "recording.started"
    EventRecordingReady      EventType = "recording.ready"
)
```

#### Dependency Injection (Constructor-based)
```go
// service/session_service.go
type SessionService struct {
    repo      port.SessionRepository
    publisher port.EventPublisher
    livekit   port.LiveKitClient
    logger    *slog.Logger
}

func NewSessionService(
    repo port.SessionRepository,
    publisher port.EventPublisher,
    livekit port.LiveKitClient,
    logger *slog.Logger,
) *SessionService {
    return &SessionService{
        repo:      repo,
        publisher: publisher,
        livekit:   livekit,
        logger:    logger,
    }
}
```

#### Middleware Chain Pattern (for HTTP)
```go
// Chi middleware composition
r := chi.NewRouter()
r.Use(middleware.RequestID)
r.Use(middleware.RealIP)
r.Use(slogMiddleware)      // structured logging
r.Use(middleware.Recoverer)
r.Use(corsHandler)
r.Use(rateLimiter)

r.Route("/v1", func(r chi.Router) {
    r.Use(apiKeyAuth)  // tenant authentication
    r.Route("/sessions", func(r chi.Router) {
        r.Post("/", createSession)
        r.Get("/{sessionID}", getSession)
        r.Post("/{sessionID}/token", generateToken)
    })
})
```

#### Circuit Breaker (for external calls)
```go
// For LiveKit client, webhook delivery, etc.
// Using simple state machine, no external dependency
type CircuitBreaker struct {
    failures    int
    threshold   int
    resetAfter  time.Duration
    lastFailure time.Time
    mu          sync.Mutex
}
```

### 5.3 Concurrency Patterns

**Graceful Shutdown:**
```go
func main() {
    ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
    defer cancel()

    // Start all servers
    g, gCtx := errgroup.WithContext(ctx)
    g.Go(func() error { return httpServer.ListenAndServe() })
    g.Go(func() error { return grpcServer.Serve(lis) })
    g.Go(func() error { return eventConsumer.Start(gCtx) })

    // Wait for shutdown signal
    g.Go(func() error {
        <-gCtx.Done()
        httpServer.Shutdown(context.Background())
        grpcServer.GracefulStop()
        return nil
    })

    g.Wait()
}
```

**Worker Pool (for webhook delivery):**
```go
type WebhookWorkerPool struct {
    jobs    chan WebhookJob
    workers int
}

func (p *WebhookWorkerPool) Start(ctx context.Context) {
    for i := 0; i < p.workers; i++ {
        go func() {
            for {
                select {
                case <-ctx.Done():
                    return
                case job := <-p.jobs:
                    p.deliver(ctx, job)
                }
            }
        }()
    }
}
```

---

## 6. Database Schemas

### 6.1 API Gateway Database (tenants, API keys)

```sql
-- Tenants (organizations integrating our platform)
CREATE TABLE tenants (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        VARCHAR(255) NOT NULL,
    domain      VARCHAR(255),
    plan        VARCHAR(50) NOT NULL DEFAULT 'free',
    is_active   BOOLEAN NOT NULL DEFAULT true,
    settings    JSONB NOT NULL DEFAULT '{}',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- API Keys (each tenant can have multiple)
CREATE TABLE api_keys (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id   UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    key_prefix  VARCHAR(8) NOT NULL,       -- First 8 chars for identification
    key_hash    VARCHAR(255) NOT NULL,      -- bcrypt hash of full key
    name        VARCHAR(255) NOT NULL,      -- Human-readable label
    scopes      TEXT[] NOT NULL DEFAULT '{}', -- ["sessions:read", "sessions:write"]
    is_active   BOOLEAN NOT NULL DEFAULT true,
    expires_at  TIMESTAMPTZ,
    last_used   TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_api_keys_prefix ON api_keys(key_prefix);
CREATE INDEX idx_api_keys_tenant ON api_keys(tenant_id);

-- Webhook Endpoints (per tenant)
CREATE TABLE webhook_endpoints (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id   UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    url         VARCHAR(2048) NOT NULL,
    secret      VARCHAR(255) NOT NULL,     -- For HMAC signing
    events      TEXT[] NOT NULL DEFAULT '{"*"}', -- Event filter
    is_active   BOOLEAN NOT NULL DEFAULT true,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_webhook_endpoints_tenant ON webhook_endpoints(tenant_id);
```

### 6.2 Session Service Database

```sql
-- Sessions (a consultation/call)
CREATE TABLE sessions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID NOT NULL,
    room_name       VARCHAR(255) NOT NULL UNIQUE,
    status          VARCHAR(50) NOT NULL DEFAULT 'waiting',
    -- Status: waiting → active → ended / cancelled
    session_type    VARCHAR(50) NOT NULL DEFAULT 'video',
    -- Type: video, audio_only, chat_only
    metadata        JSONB NOT NULL DEFAULT '{}',
    max_participants INT NOT NULL DEFAULT 2,
    scheduled_at    TIMESTAMPTZ,
    started_at      TIMESTAMPTZ,
    ended_at        TIMESTAMPTZ,
    duration_secs   INT,
    end_reason      VARCHAR(100),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_sessions_tenant ON sessions(tenant_id);
CREATE INDEX idx_sessions_status ON sessions(status);
CREATE INDEX idx_sessions_room ON sessions(room_name);
CREATE INDEX idx_sessions_created ON sessions(created_at DESC);

-- Participants in a session
CREATE TABLE participants (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id      UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    identity        VARCHAR(255) NOT NULL,  -- External user ID
    name            VARCHAR(255) NOT NULL,
    role            VARCHAR(50) NOT NULL DEFAULT 'patient',
    -- Roles: patient, nurse, doctor, observer
    status          VARCHAR(50) NOT NULL DEFAULT 'invited',
    -- Status: invited → waiting → connected → disconnected
    permissions     JSONB NOT NULL DEFAULT '{"can_publish": true, "can_subscribe": true}',
    joined_at       TIMESTAMPTZ,
    left_at         TIMESTAMPTZ,
    duration_secs   INT,
    metadata        JSONB NOT NULL DEFAULT '{}',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_participants_session ON participants(session_id);
CREATE INDEX idx_participants_identity ON participants(identity);

-- Waiting Queue (per tenant)
CREATE TABLE queue_entries (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID NOT NULL,
    session_id      UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    patient_identity VARCHAR(255) NOT NULL,
    priority        INT NOT NULL DEFAULT 0,
    position        INT NOT NULL,
    status          VARCHAR(50) NOT NULL DEFAULT 'waiting',
    -- Status: waiting → assigned → completed → expired
    assigned_to     VARCHAR(255),           -- Nurse/doctor identity
    queued_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    assigned_at     TIMESTAMPTZ,
    completed_at    TIMESTAMPTZ
);
CREATE INDEX idx_queue_tenant_status ON queue_entries(tenant_id, status);
CREATE INDEX idx_queue_position ON queue_entries(tenant_id, position);

-- Chat Messages (in-call text chat)
CREATE TABLE chat_messages (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id      UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    sender_identity VARCHAR(255) NOT NULL,
    message_type    VARCHAR(50) NOT NULL DEFAULT 'text',
    -- Types: text, file, system
    content         TEXT NOT NULL,
    metadata        JSONB NOT NULL DEFAULT '{}',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_chat_session ON chat_messages(session_id, created_at);

-- Session Notes (post-call)
CREATE TABLE session_notes (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id      UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    author_identity VARCHAR(255) NOT NULL,
    content         TEXT NOT NULL,
    is_private      BOOLEAN NOT NULL DEFAULT false,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_notes_session ON session_notes(session_id);
```

### 6.3 Recording Service Database

```sql
-- Recordings
CREATE TABLE recordings (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id      UUID NOT NULL,
    tenant_id       UUID NOT NULL,
    egress_id       VARCHAR(255),           -- LiveKit egress ID
    status          VARCHAR(50) NOT NULL DEFAULT 'pending',
    -- Status: pending → recording → processing → ready → expired → deleted
    recording_type  VARCHAR(50) NOT NULL DEFAULT 'composite',
    -- Types: composite (single video), track (separate tracks)
    storage_path    VARCHAR(2048),
    storage_bucket  VARCHAR(255),
    file_size_bytes BIGINT,
    duration_secs   INT,
    format          VARCHAR(50) DEFAULT 'mp4',
    consent_given   BOOLEAN NOT NULL DEFAULT false,
    consent_by      TEXT[] NOT NULL DEFAULT '{}',  -- Identities who consented
    expires_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_recordings_session ON recordings(session_id);
CREATE INDEX idx_recordings_tenant ON recordings(tenant_id);
CREATE INDEX idx_recordings_status ON recordings(status);
```

### 6.4 Webhook Service Database

```sql
-- Webhook Deliveries (log of all attempts)
CREATE TABLE webhook_deliveries (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    endpoint_id     UUID NOT NULL,
    tenant_id       UUID NOT NULL,
    event_type      VARCHAR(100) NOT NULL,
    payload         JSONB NOT NULL,
    response_status INT,
    response_body   TEXT,
    attempt         INT NOT NULL DEFAULT 1,
    status          VARCHAR(50) NOT NULL DEFAULT 'pending',
    -- Status: pending → delivered → failed → dead_letter
    next_retry_at   TIMESTAMPTZ,
    delivered_at    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_deliveries_status ON webhook_deliveries(status, next_retry_at);
CREATE INDEX idx_deliveries_tenant ON webhook_deliveries(tenant_id, created_at DESC);
```

---

## 7. API Design

### 7.1 REST API (Public — API Gateway)

**Base URL**: `https://api.yourplatform.com/v1`

**Authentication**: API Key in header
```
Authorization: Bearer tm_live_xxxxxxxxxxxxxxxxxxxx
```

#### Sessions

```
POST   /v1/sessions                    Create a new session
GET    /v1/sessions                    List sessions (paginated)
GET    /v1/sessions/{id}               Get session details
PATCH  /v1/sessions/{id}               Update session metadata
DELETE /v1/sessions/{id}               End/cancel session
POST   /v1/sessions/{id}/token         Generate participant token
GET    /v1/sessions/{id}/participants  List participants
GET    /v1/sessions/{id}/chat          Get chat history
GET    /v1/sessions/{id}/recordings    List recordings
```

#### Queue

```
POST   /v1/queue                       Add to waiting queue
GET    /v1/queue                       Get queue status
PATCH  /v1/queue/{id}/assign           Assign to nurse/doctor
DELETE /v1/queue/{id}                  Remove from queue
```

#### Webhooks

```
POST   /v1/webhooks                    Register webhook endpoint
GET    /v1/webhooks                    List webhook endpoints
DELETE /v1/webhooks/{id}               Remove endpoint
GET    /v1/webhooks/{id}/deliveries    Get delivery logs
```

#### TURN Credentials

```
POST   /v1/turn/credentials            Get ephemeral TURN credentials
```

### 7.2 Request/Response Examples

**Create Session:**
```json
POST /v1/sessions
{
    "type": "video",
    "max_participants": 2,
    "metadata": {
        "patient_name": "John Doe",
        "reason": "General consultation"
    },
    "participants": [
        {
            "identity": "patient-123",
            "name": "John Doe",
            "role": "patient"
        }
    ],
    "recording": {
        "auto_start": false
    },
    "webhook_url": "https://your-app.com/webhooks/telemedicine"
}
```

**Response:**
```json
{
    "id": "sess_01H8...",
    "room_name": "rm-abc123def456",
    "status": "waiting",
    "type": "video",
    "participants": [...],
    "created_at": "2026-03-09T12:00:00Z",
    "turn_servers": [
        {
            "urls": ["turn:turn.yourplatform.com:3478"],
            "username": "1741...:sess_01H8...",
            "credential": "hmac-generated-credential"
        }
    ]
}
```

**Generate Token:**
```json
POST /v1/sessions/{id}/token
{
    "identity": "nurse-456",
    "name": "Nurse Fatima",
    "role": "nurse",
    "permissions": {
        "can_publish": true,
        "can_subscribe": true,
        "can_publish_data": true,
        "hidden": false
    }
}
```

**Response:**
```json
{
    "token": "eyJhbGciOiJIUzI1NiIs...",
    "livekit_url": "wss://lk.yourplatform.com",
    "room_name": "rm-abc123def456",
    "identity": "nurse-456",
    "expires_at": "2026-03-09T13:00:00Z"
}
```

### 7.3 Webhook Event Payloads

```json
{
    "id": "evt_01H8...",
    "type": "participant.joined",
    "timestamp": "2026-03-09T12:05:00Z",
    "data": {
        "session_id": "sess_01H8...",
        "participant": {
            "identity": "nurse-456",
            "name": "Nurse Fatima",
            "role": "nurse"
        }
    }
}
```

**Webhook signature header:**
```
X-Webhook-Signature: sha256=<HMAC-SHA256 of raw body with webhook secret>
X-Webhook-ID: evt_01H8...
X-Webhook-Timestamp: 1741...
```

### 7.4 gRPC Internal API (between services)

```protobuf
syntax = "proto3";
package telemedicine.session.v1;

service SessionService {
    rpc CreateSession(CreateSessionRequest) returns (Session);
    rpc GetSession(GetSessionRequest) returns (Session);
    rpc EndSession(EndSessionRequest) returns (Session);
    rpc GenerateToken(GenerateTokenRequest) returns (TokenResponse);

    rpc AddToQueue(AddToQueueRequest) returns (QueueEntry);
    rpc AssignFromQueue(AssignFromQueueRequest) returns (QueueEntry);
    rpc GetQueueStatus(GetQueueStatusRequest) returns (QueueStatusResponse);

    // Server streaming for real-time events
    rpc SubscribeEvents(SubscribeEventsRequest) returns (stream SessionEvent);
}

message Session {
    string id = 1;
    string tenant_id = 2;
    string room_name = 3;
    SessionStatus status = 4;
    string session_type = 5;
    repeated Participant participants = 6;
    map<string, string> metadata = 7;
    google.protobuf.Timestamp created_at = 8;
    google.protobuf.Timestamp started_at = 9;
    google.protobuf.Timestamp ended_at = 10;
}

enum SessionStatus {
    SESSION_STATUS_UNSPECIFIED = 0;
    SESSION_STATUS_WAITING = 1;
    SESSION_STATUS_ACTIVE = 2;
    SESSION_STATUS_ENDED = 3;
    SESSION_STATUS_CANCELLED = 4;
}

message Participant {
    string id = 1;
    string identity = 2;
    string name = 3;
    ParticipantRole role = 4;
    ParticipantStatus status = 5;
    map<string, string> permissions = 6;
    map<string, string> metadata = 7;
}

enum ParticipantRole {
    ROLE_UNSPECIFIED = 0;
    ROLE_PATIENT = 1;
    ROLE_NURSE = 2;
    ROLE_DOCTOR = 3;
    ROLE_OBSERVER = 4;
}
```

---

## 8. Infrastructure

### 8.1 Local Development (Docker Compose)

```yaml
services:
  # --- Infrastructure ---
  postgres:
    image: postgres:17-alpine
    environment:
      POSTGRES_USER: telemedicine
      POSTGRES_PASSWORD: devpassword
      POSTGRES_DB: telemedicine
    ports: ["5432:5432"]
    volumes: [pgdata:/var/lib/postgresql/data]

  redis:
    image: redis:7-alpine
    ports: ["6379:6379"]

  minio:
    image: minio/minio
    command: server /data --console-address ":9001"
    environment:
      MINIO_ROOT_USER: minioadmin
      MINIO_ROOT_PASSWORD: minioadmin
    ports: ["9000:9000", "9001:9001"]

  # --- LiveKit ---
  livekit:
    image: livekit/livekit-server
    command: --config /etc/livekit.yaml --dev
    ports: ["7880:7880", "7881:7881", "7882:7882/udp"]
    volumes: [./config/livekit.yaml:/etc/livekit.yaml]
    depends_on: [redis]

  livekit-egress:
    image: livekit/egress
    environment:
      EGRESS_CONFIG_FILE: /etc/egress.yaml
    volumes: [./config/egress.yaml:/etc/egress.yaml]
    depends_on: [livekit]

  # --- Our Services ---
  gateway:
    build: ./services/gateway
    ports: ["8080:8080"]
    environment:
      DATABASE_URL: postgres://telemedicine:devpassword@postgres:5432/telemedicine?sslmode=disable
      REDIS_URL: redis://redis:6379
      LIVEKIT_URL: ws://livekit:7880
      LIVEKIT_API_KEY: devkey
      LIVEKIT_API_SECRET: devsecret
    depends_on: [postgres, redis, livekit]

  session:
    build: ./services/session
    ports: ["8081:8081", "9091:9091"]  # HTTP + gRPC
    environment:
      DATABASE_URL: postgres://telemedicine:devpassword@postgres:5432/telemedicine?sslmode=disable
      REDIS_URL: redis://redis:6379
      LIVEKIT_URL: http://livekit:7880
      LIVEKIT_API_KEY: devkey
      LIVEKIT_API_SECRET: devsecret
    depends_on: [postgres, redis, livekit]

  turn:
    build: ./services/turn
    ports:
      - "3478:3478/udp"
      - "3478:3478/tcp"
      - "5349:5349/tcp"
    environment:
      PUBLIC_IP: "127.0.0.1"
      REALM: telemedicine.local
      AUTH_SECRET: turnsecret

  webhook:
    build: ./services/webhook
    environment:
      DATABASE_URL: postgres://telemedicine:devpassword@postgres:5432/telemedicine?sslmode=disable
      REDIS_URL: redis://redis:6379
    depends_on: [postgres, redis]

volumes:
  pgdata:
```

### 8.2 Production Architecture

```
                    ┌─────────────┐
                    │   DNS/CDN   │
                    │ (Cloudflare)│
                    └──────┬──────┘
                           │
              ┌────────────┴────────────┐
              │                         │
       ┌──────▼──────┐          ┌──────▼──────┐
       │ Load Balancer│          │ TURN Server │
       │ (nginx/HAProxy)        │ (UDP/TCP    │
       └──────┬──────┘          │  3478/5349) │
              │                 └─────────────┘
    ┌─────────┼─────────┐
    │         │         │
┌───▼───┐┌───▼───┐┌───▼───┐
│Gateway ││Gateway││Gateway│  (horizontal scaling)
│  #1   ││  #2   ││  #3   │
└───┬───┘└───┬───┘└───┬───┘
    └─────────┼─────────┘
              │ gRPC
    ┌─────────┼─────────┐
    │         │         │
┌───▼───┐┌───▼───┐┌────▼────┐
│Session ││LiveKit││LiveKit  │
│Service ││ SFU #1││ SFU #2  │
└───┬───┘└───────┘└─────────┘
    │
┌───▼───────────────────────┐
│  PostgreSQL  │    Redis    │
│  (primary +  │  (cluster)  │
│   replica)   │             │
└──────────────┴─────────────┘
```

### 8.3 Deployment Strategy

**Phase 1 (MVP)**: Single VPS with Docker Compose
- 4 vCPU, 8GB RAM, 100GB SSD
- All services on one machine
- Good for <100 concurrent sessions
- Cost: ~$40-80/month

**Phase 2**: Multi-server
- Separate DB server (managed PostgreSQL)
- Separate TURN server (needs public IP, close to users)
- App servers behind load balancer
- Object storage for recordings

**Phase 3**: Kubernetes
- Full K8s deployment
- Auto-scaling per service
- Multi-region TURN servers
- Managed Redis cluster

---

## 9. Implementation Plan

### Phase 1: Foundation (MVP)

**Step 1**: Umbrella repo + shared module
- Git init, submodule structure
- Protobuf definitions
- Shared models and errors

**Step 2**: Session Service
- Domain models
- PostgreSQL adapter (migrations + repository)
- LiveKit integration (room CRUD, token generation)
- Redis event publisher
- gRPC server

**Step 3**: API Gateway
- Chi router + middleware
- API key authentication
- Session endpoints (proxy to session service via gRPC)
- Token generation endpoint
- CORS + rate limiting

**Step 4**: TURN Server
- Pion TURN with ephemeral credentials
- UDP + TCP listeners
- Health check endpoint

**Step 5**: Webhook Service
- Event consumer (Redis Pub/Sub)
- HTTP delivery with retry
- Delivery logging

**Step 6**: Web SDK
- TypeScript wrapper around LiveKit client SDK
- Pre-call device checker
- Embeddable widget (iframe + postMessage API)
- Simple UI: video tiles, mute/unmute, end call, chat

**Step 7**: Docker Compose + Integration Tests
- Full local environment
- End-to-end test: create session → join → video → end → webhook delivered

### Phase 2: Polish
- Recording service (LiveKit Egress integration)
- Notification service
- Queue system improvements
- Analytics endpoints
- Admin dashboard

### Phase 3: Scale
- Multi-node LiveKit
- Kubernetes manifests
- Multi-region TURN
- Mobile SDKs
- E2E encryption
