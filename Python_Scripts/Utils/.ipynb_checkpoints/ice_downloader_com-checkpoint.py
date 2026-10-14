import re
import win32com.client
from pathlib import Path
from datetime import datetime, timedelta

# ─────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────

BASE_OUTPUT_DIR = Path(r"C:\Users\mkeita9\Projects\ICE")

ICE_SUBFOLDER = "14.ICE"  # Subfolder inside Inbox

FOLDER_MAP = {
    "IFC_RebalancingProjected": BASE_OUTPUT_DIR / "IFC_RebalancingProjected",
    "IFC_Rebalancing":          BASE_OUTPUT_DIR / "IFC_Rebalancing",
    "IFC_Daily_Price":          BASE_OUTPUT_DIR / "IFC_Daily_Price",
}

# Order matters: most specific pattern first
ATTACHMENT_PATTERNS = [
    ("IFC_RebalancingProjected", re.compile(r"^IFC_RebalancingProjected_(\d{8})", re.IGNORECASE)),
    ("IFC_Rebalancing",          re.compile(r"^IFC_Rebalancing_(\d{8})", re.IGNORECASE)),
    ("IFC_Daily_Price",          re.compile(r"^IFC_Daily_Price_(\d{8})", re.IGNORECASE)),
]

# Fallback: how many days back to scan if a folder is empty
FALLBACK_DAYS = 90


# ─────────────────────────────────────────────
# CORE LOGIC
# ─────────────────────────────────────────────

def create_output_folders():
    for folder_path in FOLDER_MAP.values():
        folder_path.mkdir(parents=True, exist_ok=True)
        print(f"[+] Folder ready: {folder_path}")


def classify_attachment(filename: str):
    """
    Return (folder_key, date) for a matching filename, or (None, None) if unrecognised.
    The date is parsed from the YYYYMMDD part of the filename.
    """
    for key, pattern in ATTACHMENT_PATTERNS:
        match = pattern.match(filename)
        if match:
            date_str = match.group(1)
            file_date = datetime.strptime(date_str, "%Y%m%d")
            return key, file_date
    return None, None


def get_last_downloaded_date(folder_key: str) -> datetime:
    """
    Scan the destination folder for existing files and return the date
    of the most recently downloaded file. Falls back to FALLBACK_DAYS
    ago if the folder is empty.
    """
    folder_path = FOLDER_MAP[folder_key]
    latest_date = None

    for file in folder_path.iterdir():
        _, file_date = classify_attachment(file.name)
        if file_date and (latest_date is None or file_date > latest_date):
            latest_date = file_date

    if latest_date:
        print(f"    Last file in {folder_key}: {latest_date.strftime('%Y-%m-%d')} — scanning from that date.")
        return latest_date
    else:
        fallback = datetime.now() - timedelta(days=FALLBACK_DAYS)
        print(f"    No files found in {folder_key} — falling back to {FALLBACK_DAYS} days ago ({fallback.strftime('%Y-%m-%d')}).")
        return fallback


def get_ice_folder():
    """Connect to Outlook Classic and return the 14.ICE subfolder directly."""
    try:
        outlook = win32com.client.GetActiveObject("Outlook.Application")
        print("[+] Connected to existing Outlook session.")
    except Exception:
        try:
            outlook = win32com.client.Dispatch("Outlook.Application")
            print("[+] Connected to Outlook via Dispatch.")
        except Exception as e:
            raise RuntimeError(f"Could not connect to Outlook Classic.\nDetail: {e}")

    namespace = outlook.GetNamespace("MAPI")
    namespace.Logon()
    inbox = namespace.GetDefaultFolder(6)  # 6 = olFolderInbox

    ice_folder = inbox.Folders[ICE_SUBFOLDER]
    print(f"[+] Navigated to: Inbox \\ {ICE_SUBFOLDER} ({ice_folder.Items.Count} emails)")
    return ice_folder


def scan_and_download(ice_folder, overwrite: bool = False):
    saved_count     = 0
    skipped_count   = 0
    unmatched_count = 0

    # Determine the cutoff date per folder based on existing files
    print("\n[*] Checking last downloaded dates per folder...")
    cutoff_per_folder = {key: get_last_downloaded_date(key) for key in FOLDER_MAP}

    # Overall earliest cutoff to limit how far back we scan emails
    overall_cutoff = min(cutoff_per_folder.values())
    print(f"\n[*] Scanning emails from {overall_cutoff.strftime('%Y-%m-%d')} onwards...\n")

    messages = ice_folder.Items
    messages.Sort("[ReceivedTime]", True)  # Most recent first

    for message in messages:
        try:
            received = getattr(message, "ReceivedTime", None)

            # Stop once emails go past the overall cutoff
            if received and received.replace(tzinfo=None) < overall_cutoff:
                break

            subject  = getattr(message, "Subject", "(no subject)")
            date_str = received.strftime("%Y-%m-%d") if received else "unknown"

            attachments = message.Attachments
            if attachments.Count == 0:
                continue

            print(f"[EMAIL] {date_str} | {subject}")

            for i in range(1, attachments.Count + 1):
                attachment = attachments.Item(i)
                filename   = attachment.FileName
                folder_key, file_date = classify_attachment(filename)

                if folder_key is None:
                    print(f"    [UNMATCHED] {filename}")
                    unmatched_count += 1
                    continue

                # Skip if this file's date is on or before the last downloaded date
                if not overwrite and file_date <= cutoff_per_folder[folder_key]:
                    print(f"    [SKIP] Already covered: {filename}")
                    skipped_count += 1
                    continue

                destination = FOLDER_MAP[folder_key]
                file_path   = destination / filename

                if file_path.exists() and not overwrite:
                    print(f"    [SKIP] Already exists: {filename}")
                    skipped_count += 1
                    continue

                attachment.SaveAsFile(str(file_path))
                print(f"    [SAVED] {filename}  →  {folder_key}/")
                saved_count += 1

        except Exception as e:
            print(f"    [ERROR] {e}")
            continue

    print(f"\n{'─' * 55}")
    print(f"  Done.")
    print(f"  Saved   : {saved_count} file(s)")
    print(f"  Skipped : {skipped_count} file(s)")
    print(f"  Ignored : {unmatched_count} unmatched attachment(s)")
    print(f"{'─' * 55}\n")


def main():
    create_output_folders()
    ice_folder = get_ice_folder()
    scan_and_download(ice_folder, overwrite=False)


if __name__ == "__main__":
    main()
