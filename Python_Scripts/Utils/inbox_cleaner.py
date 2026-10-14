import win32com.client

def move_inbox_to_fy2027():
    # Connect to the running Outlook instance
    outlook = win32com.client.Dispatch("Outlook.Application")
    namespace = outlook.GetNamespace("MAPI")

    # Get the default Inbox folder
    inbox = namespace.GetDefaultFolder(6)  # 6 = olFolderInbox

    # Locate FY2027 as a subfolder of Inbox, or create it
    fy2027_folder = None
    for folder in inbox.Folders:
        if folder.Name == "FY2027":
            fy2027_folder = folder
            break

    if fy2027_folder is None:
        print("Folder 'FY2027' not found. Creating it now inside Inbox...")
        fy2027_folder = inbox.Folders.Add("FY2027")
        print("Folder 'FY2027' created successfully.")
    else:
        print("Folder 'FY2027' found.")

    # Get items directly in Inbox (not subfolders)
    messages = inbox.Items
    total = messages.Count
    print(f"Found {total} item(s) in Inbox. Starting to move...")

    moved = 0
    failed = 0

    # Iterate in reverse order (safest when moving items from a live collection)
    for i in range(total, 0, -1):
        try:
            item = messages.Item(i)
            subject = item.Subject if hasattr(item, "Subject") else "[No Subject]"
            item.Move(fy2027_folder)
            moved += 1
            print(f"  Moved ({moved}/{total}): {subject}")
        except Exception as e:
            failed += 1
            print(f"  FAILED to move item {i}: {e}")

    print(f"\nDone. Moved: {moved} | Failed: {failed}")

if __name__ == "__main__":
    move_inbox_to_fy2027()
