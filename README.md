# Rexwise

Rexwise is a Flutter Tick Cross game with single-player and two-player modes, sound effects, scoring, and animated win feedback.

## Production Setup

Android uses the production package/application ID `com.rexwise`.

To create a signed Android release, add `android/key.properties` locally with:

```properties
storeFile=/absolute/path/to/release-keystore.jks
storePassword=...
keyAlias=...
keyPassword=...
```

Build with:

```sh
flutter build appbundle --release
```
