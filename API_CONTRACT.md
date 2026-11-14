# Visitor Tagging – API Contract

The app talks to three endpoints served by the CodeIgniter 3 controller
`server/Visitor_tagging.php` (copy it to `application/controllers/`). Every
request carries the header `X-Api-Key`. The base URL can be changed on the
device from the login screen (server icon). Table for tags: `server/schema.sql`.

All times are **UTC, ISO 8601** (for example `2026-11-14T09:30:00.000Z`).
`server_time` may also be a Unix timestamp (seconds or milliseconds).

The response parser is tolerant: QR items may use `qr_code` / `qrcode` / `qr` / `code`,
categories may use `category_id` / `categoryId`, and the list may be under
`data`, `qr_codes`, `records` or `items`. A response with `"status": false` or
`"success": false` (or HTTP 4xx) is treated as an error and its `message` is shown.

---

## 0. Categories (after entering Event ID)

`GET {baseUrl}/categories?event_id=123456`

Validates the event and returns the categories the operator can tag. The list is a
static array in the controller (`TAGGING_CATEGORIES`). IDs refer to the column set in
`CATEGORY_COLUMN` (default `studio_category`).

```json
{
  "status": true,
  "event": { "id": "123456", "name": "Event 123456" },
  "data": [
    { "id": "5660", "name": "BUSINESS VISITOR" },
    { "id": "5661", "name": "BUSINESS VISITOR EWI" }
  ]
}
```

---

## 1. Event login + full download

`GET {baseUrl}/event?event_id=123456&category_id=5660`

Only QR codes in the selected category are returned. The app's category list is in
`AppConfig.taggingCategories`.

Called once when the operator enters the 6-digit Event ID.
The app replaces its local QR database with this list and saves `server_time`
(or the device's current UTC time if missing) as the sync checkpoint.

```json
{
  "status": true,
  "message": "OK",
  "server_time": "2026-11-14T09:30:00Z",
  "event": { "id": "123456", "name": "Event 123456" },
  "data": [
    { "qr_code": "BTS26-000123", "category_id": 3, "category_name": "VIP" },
    { "qr_code": "BTS26-000124", "category_id": 1, "category_name": "Visitor" }
  ]
}
```

Invalid event:

```json
{ "status": false, "message": "Invalid Event ID" }
```

---

## 2. Delta sync (every 2 minutes when online)

`GET {baseUrl}/sync?event_id=123456&since=2026-11-14T09:30:00.000Z`

Return QR codes that were **added** or whose **category changed** after `since`,
for **all** categories. The app keeps rows in its selected category and removes
rows that moved to another category.
The app upserts them into the local database and moves its checkpoint to
`server_time`.

```json
{
  "status": true,
  "server_time": "2026-11-14T09:32:00Z",
  "data": [
    { "qr_code": "BTS26-000123", "category_id": 5, "category_name": "Speaker" },
    { "qr_code": "BTS26-000999", "category_id": 1, "category_name": "Visitor" }
  ],
  "deleted": ["BTS26-000050"]
}
```

`deleted` is optional. An empty `data` array means nothing changed.

> Tip: use `server_time` from the server clock so device clock drift cannot
> cause missed updates.

---

## 3. Submit a tag (guest QR + printed card QR)

`POST {baseUrl}/tag` with `Content-Type: application/json`

```json
{
  "event_id": "123456",
  "guest_qr": "BTS26-000123",
  "card_qr": "CARD-778812",
  "category_id": "5",
  "scanned_at": "2026-11-14T09:33:12.418Z",
  "device_id": "a1b2c3d4e5f6",
  "local_id": 42
}
```

Success:

```json
{ "status": true, "message": "Tagged" }
```

Rejected (the app marks the tag as rejected and shows the message):

```json
{ "status": false, "message": "Card already assigned" }
```

Tags are saved on the device first and uploaded in order. If the device is
offline or the server returns 5xx, the tag stays in the queue and is retried
on the next sync. `device_id` + `local_id` together uniquely identify a tag,
so the server can safely ignore duplicates if a retry is received twice.
