-- ============================================================
-- HARVESTLINK v1.4 — IDENTITY & LOCATION SCHEMA
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "btree_gist";

-- ---------- EntityType registry ----------
CREATE TABLE entity_type (
  code              TEXT PRIMARY KEY,
  domain            TEXT NOT NULL,
  parent_types      TEXT[] NOT NULL DEFAULT '{}',
  child_types       TEXT[] NOT NULL DEFAULT '{}',
  id_pattern        TEXT,
  action_policy_id  UUID,
  state_machine_id  UUID,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------- Entity ----------
CREATE TABLE entity (
  uuid              UUID PRIMARY KEY,
  entity_type       TEXT NOT NULL REFERENCES entity_type(code),
  human_id          TEXT NOT NULL,
  display_name      TEXT,
  state             TEXT NOT NULL DEFAULT 'ACTIVE',
  lifecycle         TEXT NOT NULL DEFAULT 'ACTIVE',
  attributes        JSONB NOT NULL DEFAULT '{}',
  org_scope         UUID,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  retired_at        TIMESTAMPTZ,
  UNIQUE (entity_type, human_id, org_scope)
);

CREATE INDEX entity_type_idx ON entity(entity_type);
CREATE INDEX entity_scope_idx ON entity(org_scope) WHERE org_scope IS NOT NULL;

-- ---------- External identifiers (microchip, registry, OEM serial) ----------
CREATE TABLE entity_identifier (
  uuid              UUID PRIMARY KEY,
  entity_uuid       UUID NOT NULL REFERENCES entity(uuid) ON DELETE CASCADE,
  scheme            TEXT NOT NULL,
  value             TEXT NOT NULL,
  issuer            TEXT,
  is_primary        BOOLEAN NOT NULL DEFAULT false,
  payload_format    TEXT,
  valid_from        TIMESTAMPTZ NOT NULL DEFAULT now(),
  valid_to          TIMESTAMPTZ,
  UNIQUE (scheme, value, issuer)
);

CREATE INDEX entity_identifier_entity_idx ON entity_identifier(entity_uuid);

-- ---------- Relationships (typed, time-bound) ----------
CREATE TABLE entity_relationship (
  uuid              UUID PRIMARY KEY,
  from_uuid         UUID NOT NULL REFERENCES entity(uuid),
  to_uuid           UUID NOT NULL REFERENCES entity(uuid),
  rel_type          TEXT NOT NULL,
  qualifier         TEXT,
  valid_from        TIMESTAMPTZ NOT NULL DEFAULT now(),
  valid_to          TIMESTAMPTZ,
  source_event_uuid UUID,
  attributes        JSONB NOT NULL DEFAULT '{}'
);

CREATE INDEX rel_from_idx ON entity_relationship(from_uuid, rel_type) WHERE valid_to IS NULL;
CREATE INDEX rel_to_idx ON entity_relationship(to_uuid, rel_type) WHERE valid_to IS NULL;

ALTER TABLE entity_relationship
  ADD CONSTRAINT rel_no_overlap
  EXCLUDE USING gist (
    from_uuid WITH =,
    to_uuid WITH =,
    rel_type WITH =,
    tstzrange(valid_from, COALESCE(valid_to, 'infinity')) WITH &&
  );

-- ---------- Location ----------
CREATE TABLE entity_location (
  uuid              UUID PRIMARY KEY,
  entity_uuid       UUID NOT NULL REFERENCES entity(uuid),
  spatial_uuid      UUID NOT NULL REFERENCES entity(uuid),
  rel_type          TEXT NOT NULL DEFAULT 'LOCATED_IN',
  valid_from        TIMESTAMPTZ NOT NULL DEFAULT now(),
  valid_to          TIMESTAMPTZ,
  source_event_uuid UUID,
  confidence        REAL
);

CREATE INDEX loc_entity_current_idx ON entity_location(entity_uuid) WHERE valid_to IS NULL;
CREATE INDEX loc_spatial_current_idx ON entity_location(spatial_uuid) WHERE valid_to IS NULL;

ALTER TABLE entity_location
  ADD CONSTRAINT loc_no_overlap
  EXCLUDE USING gist (
    entity_uuid WITH =,
    tstzrange(valid_from, COALESCE(valid_to, 'infinity')) WITH &&
  );

-- ---------- Evidence ----------
CREATE TABLE evidence (
  uuid              UUID PRIMARY KEY,
  evidence_type     TEXT NOT NULL,
  uri               TEXT NOT NULL,
  mime_type         TEXT,
  size_bytes        BIGINT,
  hash_sha256       TEXT,
  captured_by       UUID,
  captured_at       TIMESTAMPTZ NOT NULL,
  location_uuid     UUID REFERENCES entity_location(uuid),
  context           JSONB NOT NULL DEFAULT '{}'
);

-- ---------- Event stream (append-only) ----------
CREATE TABLE entity_event (
  uuid              UUID PRIMARY KEY,
  event_type        TEXT NOT NULL,
  entity_uuid       UUID NOT NULL REFERENCES entity(uuid),
  actor_uuid        UUID,
  location_uuid     UUID REFERENCES entity_location(uuid),
  occurred_at       TIMESTAMPTZ NOT NULL,
  recorded_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  transport_class   TEXT NOT NULL,
  payload           JSONB NOT NULL DEFAULT '{}',
  evidence_uuids    UUID[] DEFAULT '{}',
  source            TEXT NOT NULL,
  idempotency_key   TEXT,
  sequence_hint     BIGINT
);

CREATE UNIQUE INDEX event_idem_idx ON entity_event(idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE INDEX event_entity_time_idx ON entity_event(entity_uuid, occurred_at DESC);
CREATE INDEX event_type_time_idx ON entity_event(event_type, occurred_at DESC);

-- ---------- Raw observations (farmer input, unprocessed) ----------
CREATE TABLE raw_observation (
  uuid                UUID PRIMARY KEY,
  subject_uuid        UUID NOT NULL REFERENCES entity(uuid),
  observer_uuid       UUID,
  captured_at         TIMESTAMPTZ NOT NULL,
  modality            TEXT NOT NULL,
  content             JSONB NOT NULL,
  derived_claim_uuids UUID[] DEFAULT '{}'
);

-- ---------- Claims ----------
CREATE TABLE claim (
  uuid                 UUID PRIMARY KEY,
  subject_uuid         UUID NOT NULL REFERENCES entity(uuid),
  property             TEXT NOT NULL,
  value                JSONB NOT NULL,
  unit                 TEXT,
  provenance           JSONB NOT NULL,
  confidence           REAL NOT NULL CHECK (confidence BETWEEN 0 AND 1),
  evidence_uuids       UUID[] DEFAULT '{}',
  derived_from         UUID[] DEFAULT '{}',
  raw_observation_uuid UUID REFERENCES raw_observation(uuid),
  valid_from           TIMESTAMPTZ NOT NULL DEFAULT now(),
  valid_to             TIMESTAMPTZ,
  supersedes_uuid      UUID REFERENCES claim(uuid),
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX claim_subject_prop_idx ON claim(subject_uuid, property);
CREATE INDEX claim_current_idx ON claim(subject_uuid, property) WHERE valid_to IS NULL;
