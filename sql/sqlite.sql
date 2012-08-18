CREATE TABLE IF NOT EXISTS sessions (
    id           CHAR(72) PRIMARY KEY,
    session_data TEXT
);

CREATE TABLE IF NOT EXISTS full_sync_before (
    client_name      CHAR(72) PRIMARY KEY,
    full_sync_before DATETIME NOT NULL
);

CREATE TABLE IF NOT EXISTS entry (
    uuid         char(36) PRIMARY KEY,
    body         TEXT NOT NULL,
    usn          INTEGER DEFAULT 0,
    dirty        INTEGER DEFAULT 0,
    created_at   DATETIME NOT NULL,
    updated_at   DATETIME
);

CREATE INDEX IF NOT EXISTS entry_usn on entry (usn);

CREATE TABLE IF NOT EXISTS client_status (
    client_name       char(72) PRIMARY KEY,
    last_update_count INTEGER DEFAULT 0,
    last_sync_time    DATETIME NOT NULL
);