# CHKDIN Visitor Tagging

Android app for handheld laser-scanner devices. An operator scans a guest's QR
and then the QR on a printed card; the pair is sent to the server.

## Flow

1. **Login** – enter the 6-digit Event ID. The full guest QR database
   (QR code + category) is downloaded to a local SQLite database and the current
   UTC time is stored as the sync checkpoint.
2. **Auto sync** – every 2 minutes (and when the app resumes) the app requests
   QR codes added or changed since the checkpoint and updates the local database.
3. **Tagging**
   - Scan the guest QR → verified against the local database, category shown.
   - Scan the printed card QR → pair saved locally and uploaded.
   - Works offline; pending tags upload automatically when the internet returns.

## Scanner support

- **Keyboard / key-wedge mode** – works out of the box (hidden input field,
  with or without an Enter suffix).
- **Broadcast / intent mode** – supported for Urovo, Newland, Sunmi, iData,
  Chainway, Seuic and Zebra DataWedge. For DataWedge or any configurable
  scanner, set the intent action to `com.chkdin.visitor_tagging.SCAN` and the
  extra key to `data`.

## Configuration

`lib/config/app_config.dart` – base URL, endpoint paths, sync interval and
validation rules. API format: see [API_CONTRACT.md](API_CONTRACT.md).

## Build

Every push to `main` builds a release APK with GitHub Actions. Download it from
the **Releases** page or from the workflow run's artifacts.

Local build:

```bash
flutter create --org com.chkdin --project-name visitor_tagging --platforms android .
flutter pub get
flutter build apk --release
```
