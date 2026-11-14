-- Flag columns used by the Visitor_tag_cron controller.
ALTER TABLE visitor_tags
    ADD COLUMN guest_synced    TINYINT      NOT NULL DEFAULT 0 COMMENT '0 pending, 1 guests updated, 2 guest not found',
    ADD COLUMN guest_synced_at DATETIME     NULL     COMMENT 'UTC',
    ADD COLUMN guest_sync_note VARCHAR(255) NULL,
    ADD INDEX idx_guest_synced (guest_synced, id);

-- The guests table has ~800k rows. Each tag looks up a guest by (event_id, qr_code),
-- so this index is required for the cron to stay fast. Skip it if a similar index exists:
--   SHOW INDEX FROM guests;
ALTER TABLE guests ADD INDEX idx_event_qr (event_id, qr_code);
