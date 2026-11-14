<?php
defined('BASEPATH') OR exit('No direct script access allowed');

/**
 * Visitor Tagging API (CodeIgniter 3)
 *
 * Place in application/controllers/Visitor_tagging.php
 *
 * Endpoints (all require header "X-Api-Key"):
 *   GET  /visitor_tagging/event?event_id=118261&category_id=93
 *   GET  /visitor_tagging/sync?event_id=118261&since=2026-11-14T09:30:00.000Z
 *   POST /visitor_tagging/tag   (JSON body)
 *
 * All times are UTC.
 */
class Visitor_tagging extends CI_Controller
{
    /** Must match AppConfig.apiKey in the app. */
    const API_KEY = 'a2cba4859fe1d8124d73781060b802f311a7ab84';

    const QR_POOL_TABLE = 'bts_qr_pool';
    const TAG_TABLE = 'visitor_tags';

    public function __construct()
    {
        parent::__construct();
        $this->load->database();

        $key = (string) $this->input->get_request_header('X-Api-Key', TRUE);
        if (!hash_equals(self::API_KEY, $key)) {
            $this->_respond(['status' => false, 'message' => 'Unauthorized'], 401);
        }

        // changed_at and scanned_at are stored in UTC.
        $this->db->query("SET time_zone = '+00:00'");
    }

    /**
     * Full download for an event and category: every QR in that category.
     * The app stores server_time and sends it to sync() as `since`.
     */
    public function event()
    {
        $eventId = $this->_event_id();
        $categoryId = trim((string) $this->input->get('category_id', TRUE));
        ini_set('memory_limit', '512M');

        // Capture the time BEFORE querying so no change is missed.
        $serverTime = gmdate('Y-m-d\TH:i:s\Z');

        $this->db
            ->select('qr_code, category_id, category_name')
            ->from(self::QR_POOL_TABLE)
            ->where('event_id', $eventId);
        if ($categoryId !== '') {
            $this->db->where('category_id', $categoryId);
        }
        $rows = $this->db->get()->result_array();

        if (empty($rows)) {
            $this->_respond([
                'status'  => false,
                'message' => $categoryId !== ''
                    ? 'No QR codes found for this Event ID and category'
                    : 'Invalid Event ID',
            ], 404);
        }

        $this->_respond([
            'status'      => true,
            'server_time' => $serverTime,
            'event'       => ['id' => $eventId, 'name' => 'Event ' . $eventId],
            'count'       => count($rows),
            'data'        => $this->_format_rows($rows),
        ]);
    }

    /**
     * Rows whose changed_at is on or after `since` (new QRs and category changes).
     *
     * Returns changes for ALL categories on purpose: the app keeps rows in its
     * selected category and removes rows that moved to another category.
     */
    public function sync()
    {
        $eventId = $this->_event_id();
        $sinceRaw = trim((string) $this->input->get('since', TRUE));

        try {
            $since = (new DateTimeImmutable($sinceRaw === '' ? '@0' : $sinceRaw))
                ->setTimezone(new DateTimeZone('UTC'))
                ->format('Y-m-d H:i:s');
        } catch (Exception $e) {
            $this->_respond(['status' => false, 'message' => 'Invalid since time'], 422);
        }

        $serverTime = gmdate('Y-m-d\TH:i:s\Z');

        // ">=" so rows changed in the same second as the last sync are not missed.
        // Re-sending a row is harmless because the app upserts.
        $rows = $this->db
            ->select('qr_code, category_id, category_name')
            ->from(self::QR_POOL_TABLE)
            ->where('event_id', $eventId)
            ->where('changed_at >=', $since)
            ->get()
            ->result_array();

        $this->_respond([
            'status'      => true,
            'server_time' => $serverTime,
            'since'       => $since,
            'count'       => count($rows),
            'data'        => $this->_format_rows($rows),
        ]);
    }

    /**
     * Stores one guest QR + printed card QR pair.
     */
    public function tag()
    {
        if ($this->input->method() !== 'post') {
            $this->_respond(['status' => false, 'message' => 'POST required'], 405);
        }

        $input = json_decode($this->input->raw_input_stream, true);
        if (!is_array($input)) {
            $this->_respond(['status' => false, 'message' => 'Invalid JSON body'], 400);
        }

        $eventId    = trim((string) ($input['event_id'] ?? ''));
        $guestQr    = trim((string) ($input['guest_qr'] ?? ''));
        $cardQr     = trim((string) ($input['card_qr'] ?? ''));
        $categoryId = trim((string) ($input['category_id'] ?? ''));
        $deviceId   = substr(trim((string) ($input['device_id'] ?? '')), 0, 64);
        $localId    = (int) ($input['local_id'] ?? 0);

        if (!preg_match('/^\d{6}$/', $eventId)) {
            $this->_respond(['status' => false, 'message' => 'Event ID must be 6 digits'], 422);
        }
        if ($guestQr === '' || $cardQr === '') {
            $this->_respond(['status' => false, 'message' => 'Guest QR and card QR are required'], 422);
        }

        try {
            $scannedAt = (new DateTimeImmutable((string) ($input['scanned_at'] ?? 'now')))
                ->setTimezone(new DateTimeZone('UTC'))
                ->format('Y-m-d H:i:s');
        } catch (Exception $e) {
            $scannedAt = gmdate('Y-m-d H:i:s');
        }

        // INSERT IGNORE + unique (device_id, local_id) makes app retries safe.
        $this->db->query(
            'INSERT IGNORE INTO ' . self::TAG_TABLE . '
                (event_id, guest_qr, card_qr, category_id, scanned_at, device_id, local_id, created_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, UTC_TIMESTAMP())',
            [$eventId, $guestQr, $cardQr, $categoryId, $scannedAt, $deviceId, $localId]
        );

        $this->_respond([
            'status'  => true,
            'message' => $this->db->affected_rows() > 0 ? 'Tagged' : 'Already received',
        ]);
    }

    // -------------------------------------------------------------------------

    private function _event_id()
    {
        $eventId = trim((string) $this->input->get('event_id', TRUE));
        if (!preg_match('/^\d{6}$/', $eventId)) {
            $this->_respond(['status' => false, 'message' => 'Event ID must be 6 digits'], 422);
        }
        return $eventId;
    }

    private function _format_rows(array $rows)
    {
        $out = [];
        foreach ($rows as $row) {
            $out[] = [
                'qr_code'       => (string) $row['qr_code'],
                'category_id'   => (string) $row['category_id'],
                'category_name' => $row['category_name'],
            ];
        }
        return $out;
    }

    private function _respond(array $body, $code = 200)
    {
        // Compress large responses (the full download can be several MB).
        if (!ini_get('zlib.output_compression') && extension_loaded('zlib')) {
            ob_start('ob_gzhandler');
        }
        http_response_code($code);
        header('Content-Type: application/json; charset=utf-8');
        header('Cache-Control: no-store');
        echo json_encode($body, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        exit;
    }
}
