import sqlite3
import json
import os
import sys
from pathlib import Path

def main():
    if len(sys.argv) < 3:
        print("Usage: python update_sqlite_profiles.py <provider> <key>")
        sys.exit(1)
        
    provider = sys.argv[1]
    key = sys.argv[2]
    
    db_path = str(Path.home() / ".openclaw" / "agents" / "main" / "agent" / "openclaw-agent.sqlite")
    if not os.path.exists(db_path):
        print(f"Database {db_path} does not exist, skipping SQLite update.")
        sys.exit(0)
        
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        
        cursor.execute("SELECT store_json FROM auth_profile_store WHERE store_key='primary';")
        row = cursor.fetchone()
        if row:
            data = json.loads(row[0])
            profile_name = f"{provider}:default"
            
            if 'profiles' not in data:
                data['profiles'] = {}
                
            if profile_name in data['profiles']:
                data['profiles'][profile_name]['key'] = key
            else:
                data['profiles'][profile_name] = {
                    "type": "api_key",
                    "provider": provider,
                    "key": key
                }
                
            new_json = json.dumps(data)
            cursor.execute("UPDATE auth_profile_store SET store_json=? WHERE store_key='primary';", (new_json,))
            conn.commit()
            print(f"Successfully updated SQLite auth_profile_store key for {profile_name}!")
        else:
            # Table is empty, create a new primary row
            data = {
                "version": 1,
                "profiles": {
                    f"{provider}:default": {
                        "type": "api_key",
                        "provider": provider,
                        "key": key
                    }
                }
            }
            cursor.execute("INSERT OR REPLACE INTO auth_profile_store (store_key, store_json, updated_at) VALUES ('primary', ?, ?);", 
                           (json.dumps(data), 0))
            conn.commit()
            print(f"Successfully initialized and saved profile {provider}:default in SQLite!")
            
        conn.close()
    except Exception as e:
        print(f"Error updating SQLite: {e}")

if __name__ == "__main__":
    main()
