# Video Downloader

Flutter Android app for direct video file URLs (MP4, MOV, M4V, WEBM, MKV, 3GP).

## Features
- Dark premium interface
- Direct-link downloads with progress and cancel
- Local download history, open, share, and delete
- Optional Supabase download-event logging
- GitHub Actions release APK build

## Platform limitations
TikTok, Facebook and Instagram page/share URLs are not direct video files. This app does not scrape private endpoints or bypass authentication, DRM, or platform restrictions. Use each service's official save/download feature where available. Direct video file URLs work when the host permits access.

## Supabase
The app works without Supabase. When the existing project is restored and its API key is available, add these GitHub Actions repository secrets:
- `SUPABASE_URL` = `https://zvvunloioibcmfnzzlwf.supabase.co`
- `SUPABASE_PUBLISHABLE_KEY` = the project's publishable key (never use a service_role or secret key in a mobile app).

Run `supabase/migrations/202611030001_download_events.sql` in the Supabase SQL Editor.

## Build
Open GitHub Actions -> Build Video Downloader APK -> Run workflow. Download the APK from the workflow artifact.
