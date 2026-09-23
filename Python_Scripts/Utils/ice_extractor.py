import win32com.client
import os
import re
from pathlib import Path

# ──────────────────────────────────────────────
# CONFIGURATION
# ──────────────────────────────────────────────

ACCOUNT_INDEX = 1           # mkeita9@ifc.org
ICE_FOLDER_NAME = "14.ICE"  # Nom exact du dossier dans l'Inbox
SENDER_EMAIL = "ICEIndices@ice.com"

BASE_OUTPUT_DIR = r"C:\Users\mkeita9\OneDrive - WBG\1. Work Documents\4. Projects & Initiatives\Murex_Testing_LAM_Cash\02_ICE_Benchmark\02_Input_Data\ICE_Attachments"

CATEGORIES = {
    "daily_price_IFC":              r"daily_price_IFC_\d{8}\.csv",
    "daily_price_IFCProjected":     r"daily_price_IFCProjected_\d{8}\.csv",
    "rebalancing":                  r"rebalancing_\d{8}\.csv",
    "rebalancingProjected":         r"rebalancingProjected_\d{8}\.csv",
    "IFC_Daily_Price":              r"IFC_Daily_Price_\d{8}\.csv",
    "IFC_Rebalancing":              r"IFC_Rebalancing_\d{8}\.csv",
    "IFC_RebalancingProjected":     r"IFC_RebalancingProjected_\d{8}\.csv",
}

CATEGORY_FOLDERS = {
    "daily_price_IFC":              "01_daily_price_IFC",
    "daily_price_IFCProjected":     "02_daily_price_IFCProjected",
    "rebalancing":                  "03_rebalancing",
    "rebalancingProjected":         "04_rebalancingProjected",
    "IFC_Daily_Price":              "05_IFC_Daily_Price",
    "IFC_Rebalancing":              "06_IFC_Rebalancing",
    "IFC_RebalancingProjected":     "07_IFC_RebalancingProjected",
}


# ──────────────────────────────────────────────
# FONCTIONS UTILITAIRES
# ──────────────────────────────────────────────

def get_category(filename: str):
    """Retourne la categorie du fichier selon son nom (casse stricte)."""
    for category, pattern in CATEGORIES.items():
        if re.fullmatch(pattern, filename):
            return category
    return None


def create_output_dirs(base_dir: str) -> dict:
    """Cree les repertoires de sortie et retourne un mapping categorie -> chemin."""
    dirs = {}
    for category, folder_name in CATEGORY_FOLDERS.items():
        path = Path(base_dir) / folder_name
        path.mkdir(parents=True, exist_ok=True)
        dirs[category] = path
    return dirs


def save_attachment(attachment, dest_folder: Path, overwrite: bool = False) -> bool:
    """Sauvegarde une piece jointe dans le dossier destination."""
    dest_path = dest_folder / attachment.FileName
    if dest_path.exists() and not overwrite:
        print(f"    [SKIP]  Deja existant : {attachment.FileName}")
        return False
    attachment.SaveAsFile(str(dest_path))
    print(f"    [OK]    Sauvegarde    : {attachment.FileName} -> {dest_folder.name}")
    return True


# ──────────────────────────────────────────────
# SCRIPT PRINCIPAL
# ──────────────────────────────────────────────

def main():
    print("=" * 60)
    print("  ICE Outlook Attachment Extractor")
    print("=" * 60)

    # 1. Connexion au bon compte
    print("\n[1/4] Connexion a Outlook...")
    outlook = win32com.client.Dispatch("Outlook.Application")
    namespace = outlook.GetNamespace("MAPI")
    store = namespace.Stores[ACCOUNT_INDEX]
    inbox = store.GetDefaultFolder(6)
    print(f"      Compte : {store.DisplayName}")

    # 2. Navigation vers le dossier 14.ICE
    print(f"\n[2/4] Recherche du dossier '{ICE_FOLDER_NAME}'...")
    ice_folder = None
    for folder in inbox.Folders:
        if folder.Name == ICE_FOLDER_NAME:
            ice_folder = folder
            break

    if ice_folder is None:
        print(f"ERREUR : Dossier '{ICE_FOLDER_NAME}' introuvable dans l'Inbox.")
        return

    print(f"      Dossier trouve : {ice_folder.Name} ({ice_folder.Items.Count} email(s))")

    # 3. Creation des repertoires de sortie
    print(f"\n[3/4] Creation des repertoires dans : {BASE_OUTPUT_DIR}")
    output_dirs = create_output_dirs(BASE_OUTPUT_DIR)
    for cat, path in output_dirs.items():
        print(f"      {CATEGORY_FOLDERS[cat]} : {path}")

    # 4. Traitement des emails
    print(f"\n[4/4] Traitement des emails de '{SENDER_EMAIL}'...\n")

    total_saved = 0
    total_skipped = 0
    total_unknown = 0
    emails_processed = 0

    items = ice_folder.Items
    items.Sort("[ReceivedTime]", False)  # Du plus ancien au plus recent

    for i in range(1, items.Count + 1):
        try:
            mail = items[i]

            # Filtre sur l'expediteur
            try:
                sender = mail.SenderEmailAddress.lower()
            except AttributeError:
                continue

            if SENDER_EMAIL.lower() not in sender:
                continue

            emails_processed += 1
            subject = mail.Subject or "(sans objet)"
            received = mail.ReceivedTime.strftime("%Y-%m-%d %H:%M") if mail.ReceivedTime else "?"
            print(f"  Email #{emails_processed} | {received} | {subject}")

            if mail.Attachments.Count == 0:
                print("    [INFO] Aucune piece jointe.")
                continue

            for attachment in mail.Attachments:
                filename = attachment.FileName

                if not filename.lower().endswith(".csv"):
                    print(f"    [SKIP] Non-CSV ignore : {filename}")
                    continue

                category = get_category(filename)

                if category is None:
                    print(f"    [???]  Categorie inconnue : {filename}")
                    total_unknown += 1
                    continue

                saved = save_attachment(attachment, output_dirs[category], overwrite=False)
                if saved:
                    total_saved += 1
                else:
                    total_skipped += 1

        except Exception as e:
            print(f"    [ERREUR] Email #{i} : {e}")
            continue

    # Resume
    print("\n" + "=" * 60)
    print("  RESUME")
    print("=" * 60)
    print(f"  Emails traites (ICEIndices@ice.com) : {emails_processed}")
    print(f"  Fichiers sauvegardes                : {total_saved}")
    print(f"  Fichiers ignores (deja existants)   : {total_skipped}")
    print(f"  Fichiers de categorie inconnue      : {total_unknown}")
    print(f"  Repertoire de sortie                : {BASE_OUTPUT_DIR}")
    print("=" * 60)


if __name__ == "__main__":
    main()
