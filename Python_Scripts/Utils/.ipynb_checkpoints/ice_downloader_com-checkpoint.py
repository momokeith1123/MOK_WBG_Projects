import re
import win32com.client
from pathlib import Path
from datetime import datetime, timedelta

# ─────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────

BASE_OUTPUT_DIR = Path(r"C:\Users\mkeita9\Projects")

ICE_SUBFOLDER = "14.ICE"  # Subfolder inside Inbox

FOLDER_MAP = {
    "IFC_RebalancingProjected": BASE_OUTPUT_DIR / "IFC_RebalancingProjected",
    "IFC_Rebalancing":          BASE_OUTPUT_DIR / "IFC_Rebalancing",
    "IFC_Daily_Price":          BASE_OUTPUT_DIR / "IFC_Daily_Price",
}

# Order matters: most specific pattern first
ATTACHMENT_PATTERNS = [
    ("IFC_RebalancingProjected", re.compile(r"^IFC_RebalancingProjected_\d{8}", re.IGNORECASE)),
    ("IFC_Rebalancing",          re.compile(r"^IFC_Rebalancing_\d{8}", re.IGNORECASE)),
    ("IFC_Daily_Price",          re.compile(r"^IFC_Daily_Price_\d{8}", re.IGNORECASE)),
]

SCAN_LAST_N_DAYS = 90


# ─────────────────────────────────────────────
# CORE LOGIC
# ─────────────────────────────────────────────

def create_output_folders():
    for folder_path in FOLDER_MAP.values():
        folder_path.mkdir(parents=True, exist_ok=True)
        print(f"[+] Folder ready: {folder_path}")


def classify_attachment(filename: str) -> str | None:
    for key, pattern in ATTACHMENT_PATTERNS:
        if pattern.match(filename):
            return key
    return None


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

    messages = ice_folder.Items
    messages.Sort("[ReceivedTime]", True)  # Most recent first

    cutoff = datetime.now() - timedelta(days=SCAN_LAST_N_DAYS)
    print(f"\n[*] Scanning emails since {cutoff.strftime('%Y-%m-%d')}...\n")

    for message in messages:
        try:
            received = getattr(message, "ReceivedTime", None)

            # Stop once emails go past the cutoff (sorted newest first)
            if received and received.replace(tzinfo=None) < cutoff:
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
                folder_key = classify_attachment(filename)

                if folder_key is None:
                    print(f"    [UNMATCHED] {filename}")
                    unmatched_count += 1
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
    print(f"  Skipped : {skipped_count} file(s) (already on disk)")
    print(f"  Ignored : {unmatched_count} unmatched attachment(s)")
    print(f"{'─' * 55}\n")


def main():
    create_output_folders()
    ice_folder = get_ice_folder()
    scan_and_download(ice_folder, overwrite=False)


if __name__ == "__main__":
    main()
