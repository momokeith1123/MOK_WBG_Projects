import win32com.client

TARGET_FOLDER_NAME = "FY2026"
ACCOUNT_INDEX = 1  # mkeita9@ifc.org

def main():
    print("=" * 60)
    print("  Inbox Cleaner — Move emails to folder '2026'")
    print("=" * 60)

    # 1. Connexion au bon compte
    print("\n[1/3] Connexion à Outlook...")
    outlook = win32com.client.Dispatch("Outlook.Application")
    namespace = outlook.GetNamespace("MAPI")

    store = namespace.Stores[ACCOUNT_INDEX]
    inbox = store.GetDefaultFolder(6)
    print(f"      Compte   : {store.DisplayName}")
    print(f"      Inbox    : {inbox.Items.Count} élément(s)")

    # 2. Création du dossier "2026" si inexistant
    print(f"\n[2/3] Vérification/création du dossier '{TARGET_FOLDER_NAME}'...")
    target_folder = None
    for folder in inbox.Folders:
        if folder.Name == TARGET_FOLDER_NAME:
            target_folder = folder
            print(f"      Dossier '{TARGET_FOLDER_NAME}' déjà existant.")
            break

    if target_folder is None:
        target_folder = inbox.Folders.Add(TARGET_FOLDER_NAME)
        print(f"      Dossier '{TARGET_FOLDER_NAME}' créé avec succès.")

    # 3. Déplacement des emails (à l'envers pour éviter les décalages d'index)
    print(f"\n[3/3] Déplacement des emails vers '{TARGET_FOLDER_NAME}'...")

    total = 0
    errors = 0
    items = inbox.Items
    count = items.Count

    for i in range(count, 0, -1):
        try:
            item = items[i]
            item.Move(target_folder)
            total += 1
            if total % 50 == 0:
                print(f"      {total} emails déplacés...")
        except Exception as e:
            print(f"      [ERREUR] Item #{i} : {e}")
            errors += 1
            continue

    print("\n" + "=" * 60)
    print("  RÉSUMÉ")
    print("=" * 60)
    print(f"  Compte cible                : {store.DisplayName}")
    print(f"  Emails déplacés avec succès : {total}")
    print(f"  Erreurs                     : {errors}")
    print(f"  Destination                 : Inbox > {TARGET_FOLDER_NAME}")
    print("=" * 60)

if __name__ == "__main__":
    main()
