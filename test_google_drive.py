from google.oauth2 import service_account
from googleapiclient.discovery import build

CREDENTIALS = r"D:\MIDHUN\MOBILE_APP\bbmp-pole-images-dfb8de1e3f03.json"

SCOPES = ["https://www.googleapis.com/auth/drive"]

credentials = service_account.Credentials.from_service_account_file(
    CREDENTIALS,
    scopes=SCOPES,
)

drive = build("drive", "v3", credentials=credentials)

result = drive.files().list(
    q="name='BBMP POLE IMAGES' and mimeType='application/vnd.google-apps.folder' and trashed=false",
    fields="files(id,name)",
).execute()

print("Google Drive connection successful!")
print("Folders found:")
print(result.get("files", []))