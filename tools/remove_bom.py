import os

files_to_fix = [
    r"C:\Users\10979\.openclaw\openclaw.json",
    r"C:\Users\10979\.openclaw\auth-profiles.json",
    r"C:\Users\10979\.openclaw\config.yml",
    r"C:\Users\10979\.openclaw\agents\main\agent\auth-profiles.json"
]

def remove_bom(file_path):
    if not os.path.exists(file_path):
        print(f"File not found: {file_path}")
        return
        
    try:
        # Read with utf-8-sig to automatically strip BOM
        with open(file_path, 'r', encoding='utf-8-sig') as f:
            content = f.read()
            
        # Write back with standard utf-8 (no BOM)
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(content)
            
        print(f"Successfully removed BOM from {file_path}")
    except Exception as e:
        print(f"Error processing {file_path}: {e}")

if __name__ == "__main__":
    for path in files_to_fix:
        remove_bom(path)
