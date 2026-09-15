import os

from dotenv import load_dotenv
from google.oauth2 import service_account
from googleapiclient.discovery import build


load_dotenv()

credentials_file = os.getenv("GOOGLE_SERVICE_ACCOUNT_FILE")
folder_id = os.getenv("GOOGLE_DRIVE_FOLDER_ID")
sheet_id = os.getenv("GOOGLE_SHEET_ID")

print("Credentials file:", credentials_file)
print("Drive folder ID:", folder_id)
print("Sheet ID:", sheet_id)

if not credentials_file:
    raise RuntimeError("GOOGLE_SERVICE_ACCOUNT_FILE is missing in .env")

if not folder_id:
    raise RuntimeError("GOOGLE_DRIVE_FOLDER_ID is missing in .env")

if not sheet_id or sheet_id == "YOUR_GOOGLE_SHEET_ID":
    raise RuntimeError("Please set the actual GOOGLE_SHEET_ID in .env")

if not os.path.exists(credentials_file):
    raise FileNotFoundError(
        f"Credential file not found: {credentials_file}"
    )

scopes = [
    "https://www.googleapis.com/auth/drive",
    "https://www.googleapis.com/auth/spreadsheets",
]

credentials = service_account.Credentials.from_service_account_file(
    credentials_file,
    scopes=scopes,
)

drive_service = build(
    "drive",
    "v3",
    credentials=credentials,
)

sheets_service = build(
    "sheets",
    "v4",
    credentials=credentials,
)

folder = drive_service.files().get(
    fileId=folder_id,
    fields="id,name,mimeType",
).execute()

print("\nDrive folder connected successfully:")
print(folder)

spreadsheet = sheets_service.spreadsheets().get(
    spreadsheetId=sheet_id,
).execute()

print("\nGoogle Sheet connected successfully:")
print("Title:", spreadsheet["properties"]["title"])

print("\nGoogle Drive and Google Sheets authentication successful.")