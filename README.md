# KHATA

Flutter hisab, farm-water, and document manager with local media copies and
Google Drive ZIP backup/restore.

## Run and build

```sh
flutter pub get
flutter run
flutter build apk --release
```

The GitHub Actions workflow builds and uploads a release APK on every push.

## Google Drive setup

Enable the Google Drive API in a Google Cloud project, configure an Android
OAuth client for application ID `com.example.khata` and the signing
certificate fingerprints used to build the app, and complete the OAuth consent
screen setup. Drive backup uses the `drive.file` scope.

## Local media storage

KHATA requests Android all-files access to use
`/storage/emulated/0/KHATA`. If access is unavailable, the app uses its private
application documents folder. The selected storage directory can be changed in
Settings; saved media and the JSON database are copied when changing folders.
