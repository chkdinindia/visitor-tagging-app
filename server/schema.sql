-- Stores guest QR + printed card QR pairs sent by the Visitor Tagging app.
CREATE TABLE IF NOT EXISTS visitor_tags (
    id           BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    event_id     VARCHAR(10)  NOT NULL,
    guest_qr     VARCHAR(64)  NOT NULL,
    card_qr      VARCHAR(64)  NOT NULL,
    category_id  VARCHAR(20)  NULL,
    scanned_at   DATETIME     NOT NULL COMMENT 'UTC, time of scan on the device',
    device_id    VARCHAR(64)  NOT NULL,
    local_id     INT UNSIGNED NOT NULL COMMENT 'Row ID on the device',
    created_at   DATETIME     NOT NULL COMMENT 'UTC, time received by server',
    UNIQUE KEY uq_device_local (device_id, local_id),
    KEY idx_event_guest (event_id, guest_qr),
    KEY idx_event_card (event_id, card_qr)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Recommended for fast sync queries on the QR pool.
-- ALTER TABLE bts_qr_pool ADD INDEX idx_event_changed (event_id, changed_at);
