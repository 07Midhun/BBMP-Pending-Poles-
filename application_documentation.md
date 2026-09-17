# BBMP Pending Poles - Application Documentation

This document provides a comprehensive overview of the **BBMP Pending Poles** mobile application and its backend infrastructure. It explains how the API connections work, how the system is integrated, where the source code is located, and the necessary requirements for publishing this as a mobile application.

---

## 1. System Architecture Overview

The system is divided into two main components:
1.  **Backend (Python/FastAPI):** A cloud-hosted API that acts as a bridge between the mobile app and Google Drive/Google Sheets.
2.  **Frontend (Flutter Mobile App):** An Android application that allows field technicians to view poles, filter by location, and upload images even when offline.

### How it works (The Flow)
1.  The **Backend** fetches live pending pole data directly from the external **IoT Platform (ThingsBoard / Schnell IoT)** via their API.
2.  The **Mobile App** calls the backend endpoints (e.g., when filtering or hitting refresh) to download this list of pending poles and saves them to a local SQLite database on the phone.
3.  When a technician captures images for a pole in the **Mobile App**, those images are saved locally on their phone.
4.  A background sync service in the **Mobile App** detects when the phone has internet access and uploads these images to the **Backend**.
5.  The **Backend** receives the images, uploads them to specific folders in **Google Drive**, and then logs the completion by updating a **Google Sheet** with the timestamps and links to those uploaded images.

---

## 2. Source Code Locations

The codebase is organized into two primary folders within your main `MOBILE_APP` directory:

### A. The Backend Source Code
**Location:** `C:\MOBILE_APP\MOBILE_APP\backend`
*   `main.py`: The core FastAPI application containing all the API endpoints and logic for interacting with Google Drive/Sheets.
*   `requirements.txt`: A list of all Python dependencies required to run the backend.
*   `.env`: The environment variables file containing sensitive credentials (like the Google Service Account JSON string and folder IDs).
*   **Deployment:** The backend is currently deployed to **Vercel** (`bbmp-pending-poles-jljy.vercel.app`). The configuration for this deployment is located in the root directory file `vercel.json`.

### B. The Mobile App Source Code (For Publishing)
**Location:** `C:\MOBILE_APP\MOBILE_APP\mobile`
*   `lib/main.dart`: The entry point of the Flutter application. It handles routing and checking if the user is logged in.
*   `lib/screens/`: Contains the UI code for the app, including `login_screen.dart` and `home_screen.dart` (the main table view).
*   `lib/services/`: Contains the core logic for the app:
    *   `api_service.dart`: Handles HTTP requests to your Vercel backend.
    *   `database_service.dart`: Manages the local SQLite database for offline storage.
    *   `sync_service.dart`: Manages the background uploading of images when the device comes online.
*   `pubspec.yaml`: Contains the Flutter dependencies (like `http`, `sqflite`, `shared_preferences`) and asset declarations (like your logo).
*   **For Publishing:** The main output file you generate to install on Android phones is the APK file. When you run `flutter build apk`, the final built application is located at:
    `C:\MOBILE_APP\MOBILE_APP\mobile\build\app\outputs\flutter-apk\app-release.apk`

---

## 3. API Connection and Endpoints

The mobile app communicates with the Vercel-hosted backend using HTTP REST APIs. The base URL for the backend is:
`https://bbmp-pending-poles-jljy.vercel.app`

### Key Endpoints:

1.  **GET `/api/v1/health`**
    *   **Purpose:** A simple check to ensure the backend is running.
    *   **App Usage:** Used to verify network connectivity before attempting to sync.

2.  **GET `/api/v1/google-drive/status`**
    *   **Purpose:** Verifies that the backend successfully authenticated with Google Drive and Google Sheets using the provided Service Account credentials.

3.  **POST `/api/v1/poles/filter`**
    *   **Purpose:** Fetches the live list of pending poles directly from the IoT Platform (ThingsBoard) based on the user's selected region, zone, etc.
    *   **App Usage:** The `api_service.dart` calls this when filtering or fetching the initial list of poles. It downloads the JSON array of poles and saves them to the local SQLite database.

4.  **POST `/api/v1/poles/{pole_number}/images`**
    *   **Purpose:** Accepts uploaded images for a specific pole, uploads them to Google Drive, and updates the Google Sheet.
    *   **App Usage:** The `sync_service.dart` calls this endpoint, sending the image files via `multipart/form-data`. It includes metadata like the technician's name and coordinates.

### How Integration Works (Security & Environment)
The backend requires a Google Service Account to interact with Google Drive and Sheets without requiring a human to log in. These credentials are provided to the backend via environment variables (in the `.env` file locally, and in the Vercel dashboard settings for production).
The mobile app does not hold these secrets; it only communicates with your backend, keeping your Google credentials completely secure.

---

## 4. Mobile App Publishing Requirements

If you want to distribute this application to your technicians, you have already completed the major steps! Here is a breakdown of what is required and what has been done:

### Completed Requirements:
1.  **App Icon (Logo):** The custom `assets/logo.jpg` was successfully integrated into the app using the `flutter_launcher_icons` package. This is what users will see on their phone's home screen.
2.  **Authentication (Login):** A local authentication system using `shared_preferences` was built. Users must create an account on first launch and log in on subsequent launches, securing the app.
3.  **Offline Capability:** The app uses `sqflite` to store data locally, ensuring technicians can use the app in areas with poor internet connectivity.
4.  **Release APK Generation:** We have successfully compiled the Release APK (`app-release.apk`). This is the optimized, production-ready file.

### Distributing the App (Next Steps):

**Option A: Direct Distribution (Current Method)**
You can directly share the `app-release.apk` file (located in `mobile\build\app\outputs\flutter-apk\`) with your technicians via WhatsApp, Email, or a shared drive.
*   **Requirement:** Technicians will need to enable "Install from Unknown Sources" on their Android devices to install the file.

**Option B: Google Play Store (Optional)**
If you wish to publish this on the official Google Play Store, you would need to:
1.  **Create a Google Play Developer Account:** This costs a one-time fee of $25.
2.  **App Signing:** You must generate a cryptographic Keystore to sign the app. This proves you are the author of the app and prevents others from publishing malicious updates over your app.
3.  **App Bundle (.aab):** Instead of running `flutter build apk`, you would run `flutter build appbundle`. Google Play requires `.aab` files instead of `.apk` files.
4.  **Store Listing:** You would need to provide screenshots, a privacy policy URL, and a description in the Google Play Console.

*Note: For an internal enterprise tool used by a specific set of technicians, Option A (Direct Distribution of the APK) is usually the easiest and most common approach.*

---

## Summary of Maintenance

*   **To update the App UI/Features:** Edit the dart files in `mobile/lib/`, test locally, and run `flutter build apk` to generate a new version.
*   **To update the Backend Logic:** Edit `backend/main.py`, test locally, and push the changes to GitHub. Vercel will automatically detect the changes on GitHub and redeploy the new backend to `bbmp-pending-poles-jljy.vercel.app` within a few minutes.
