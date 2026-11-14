<?php
defined('BASEPATH') OR exit('No direct script access allowed');

/**
 * Visitor Tagging - copies tagged card QRs into guests.additional_qr_code.
 *
 * Place in application/controllers/Visitor_tag_cron.php
 * Command line:
 *   php index.php visitor_tag_cron run              Process pending tags
 *   php index.php visitor_tag_cron retry_not_found  Re-queue tags whose guest was not found
 *
 * URL (requires ?key=CRON_KEY):
 *   https://studio.chkdin.com/visitor_tag_cron/run?key=...
 *   https://studio.chkdin.com/visitor_tag_cron/retry_not_found?key=...
 *
 * visitor_tags.guest_synced:
 *   0 = pending, 1 = guests table updated, 2 = guest not found
 */
class Visitor_tag_cron extends CI_Controller
{
    /** Secret for running the cron from a URL. Command line runs do not need it. */
    const CRON_KEY = 'ff8efd96c629869c3399fd672922771e';

    const TAG_TABLE = 'visitor_tags';
    const GUEST_TABLE = 'guests';

    /** Maximum tags processed per run. */
    const BATCH_SIZE = 500;

    const STATUS_PENDING = 0;
    const STATUS_UPDATED = 1;
    const STATUS_GUEST_NOT_FOUND = 2;

    public function __construct()
    {
        parent::__construct();
        if (!is_cli()) {
            $key = (string) $this->input->get('key', TRUE);
            if (!hash_equals(self::CRON_KEY, $key)) {
                show_404();
            }
            header('Content-Type: text/plain; charset=utf-8');
            header('Cache-Control: no-store');
        }
        $this->load->database();
        $this->db->query("SET time_zone = '+00:00'");
    }

    public function run()
    {
        $started = microtime(true);

        // Oldest first, so if a guest was tagged twice the latest card wins.
        $tags = $this->db
            ->select('id, event_id, guest_qr, card_qr')
            ->from(self::TAG_TABLE)
            ->where('guest_synced', self::STATUS_PENDING)
            ->order_by('id', 'ASC')
            ->limit(self::BATCH_SIZE)
            ->get()
            ->result_array();

        $updated = 0;
        $notFound = 0;

        foreach ($tags as $tag) {
            $guestCount = $this->db
                ->where('event_id', $tag['event_id'])
                ->where('qr_code', $tag['guest_qr'])
                ->count_all_results(self::GUEST_TABLE);

            if ($guestCount === 0) {
                $this->_mark($tag['id'], self::STATUS_GUEST_NOT_FOUND, 'Guest not found');
                $notFound++;
                continue;
            }

            $this->db
                ->where('event_id', $tag['event_id'])
                ->where('qr_code', $tag['guest_qr'])
                ->update(self::GUEST_TABLE, ['additional_qr_code' => $tag['card_qr']]);

            $this->_mark($tag['id'], self::STATUS_UPDATED, null);
            $updated++;
        }

        printf(
            "[%s UTC] processed=%d updated=%d guest_not_found=%d time=%.2fs\n",
            gmdate('Y-m-d H:i:s'),
            count($tags),
            $updated,
            $notFound,
            microtime(true) - $started
        );
    }

    /** Moves "guest not found" tags back to pending, e.g. after guests were imported. */
    public function retry_not_found()
    {
        $this->db
            ->where('guest_synced', self::STATUS_GUEST_NOT_FOUND)
            ->update(self::TAG_TABLE, [
                'guest_synced'    => self::STATUS_PENDING,
                'guest_sync_note' => null,
            ]);
        printf("Re-queued %d tag(s)\n", $this->db->affected_rows());
    }

    private function _mark($id, $status, $note)
    {
        $this->db
            ->where('id', $id)
            ->update(self::TAG_TABLE, [
                'guest_synced'    => $status,
                'guest_synced_at' => gmdate('Y-m-d H:i:s'),
                'guest_sync_note' => $note,
            ]);
    }
}
