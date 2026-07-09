import os
import json
import shutil
import datetime
import re
from pathlib import Path

home = Path.home()
openclaw_dir = str(home / ".openclaw")
openclaw_json_path = os.path.join(openclaw_dir, "openclaw.json")
auth_profiles_path = os.path.join(openclaw_dir, "auth-profiles.json")
config_yml_path = os.path.join(openclaw_dir, "config.yml")
cline_providers_path = str(home / ".cline" / "data" / "settings" / "providers.json")

timestamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")

def backup_file(path):
    if os.path.exists(path):
        backup_path = f"{path}.bak.{timestamp}"
        shutil.copy2(path, backup_path)
        print(f"Backed up {path} to {backup_path}")
        return True
    return False

def main():
    target_model_id = "deepseek-v4-pro"
    target_provider = "deepseek"
    target_key = "<DEEPSEEK_API_KEY_REDACTED>"
    
    # 1. Update openclaw.json
    if os.path.exists(openclaw_json_path):
        backup_file(openclaw_json_path)
        
        with open(openclaw_json_path, 'r', encoding='utf-8-sig') as f:
            config = json.load(f)
            
        # Update primary model to deepseek/deepseek-v4-pro
        if "agents" in config and "defaults" in config["agents"]:
            if "model" in config["agents"]["defaults"]:
                config["agents"]["defaults"]["model"]["primary"] = f"{target_provider}/{target_model_id}"
            
            if "models" not in config["agents"]["defaults"]:
                config["agents"]["defaults"]["models"] = {}
            # Clear old default models to make sure deepseek-v4-pro is preferred
            config["agents"]["defaults"]["models"][f"{target_provider}/{target_model_id}"] = {}
            
        # Register auth profile for deepseek
        if "auth" not in config:
            config["auth"] = {}
        if "profiles" not in config["auth"]:
            config["auth"]["profiles"] = {}
        
        config["auth"]["profiles"][f"{target_provider}:default"] = {
            "provider": target_provider,
            "mode": "api_key"
        }
            
        # Register provider and model in models.providers
        if "models" not in config:
            config["models"] = {}
        if "providers" not in config["models"]:
            config["models"]["providers"] = {}
            
        # Add deepseek provider config
        config["models"]["providers"][target_provider] = {
            "baseUrl": "https://api.deepseek.com",
            "models": [
                {
                    "id": target_model_id,
                    "name": target_model_id,
                    "reasoning": True,
                    "input": ["text"],
                    "cost": {
                        "input": 0.000002,
                        "output": 0.000008,
                        "cacheRead": 0.000001,
                        "cacheWrite": 0.000002
                    },
                    "contextWindow": 64000,
                    "contextTokens": 64000,
                    "maxTokens": 8192
                }
            ],
            "api": "openai-completions"
        }
        print(f"Registered {target_provider} and model {target_model_id} in openclaw.json")
            
        with open(openclaw_json_path, 'w', encoding='utf-8') as f:
            json.dump(config, f, indent=2, ensure_ascii=False)
            print("Successfully updated openclaw.json")

    # 2. Update auth-profiles.json
    if os.path.exists(auth_profiles_path):
        backup_file(auth_profiles_path)
        
        with open(auth_profiles_path, 'r', encoding='utf-8-sig') as f:
            auth_config = json.load(f)
            
        if "profiles" not in auth_config:
            auth_config["profiles"] = {}
            
        auth_config["profiles"][f"{target_provider}:default"] = {
            "type": "api_key",
            "provider": target_provider,
            "key": target_key
        }
        
        with open(auth_profiles_path, 'w', encoding='utf-8') as f:
            json.dump(auth_config, f, indent=4, ensure_ascii=False)
            print("Successfully updated auth-profiles.json")

    # 3. Update config.yml
    if os.path.exists(config_yml_path):
        backup_file(config_yml_path)
        
        with open(config_yml_path, 'r', encoding='utf-8-sig') as f:
            content = f.read()
            
        # update provider, api_key, base_url, model
        content = re.sub(r'provider:\s*["\']?[\w.-]+["\']?', f'provider: "{target_provider}"', content)
        content = re.sub(r'api_key:\s*["\']?[\w.-]+["\']?', f'api_key: "{target_key}"', content)
        content = re.sub(r'base_url:\s*["\']?https?://[\w.-]+(?:/[\w.-]*)*["\']?', f'base_url: "https://api.deepseek.com"', content)
        content = re.sub(r'model:\s*["\']?[\w.-]+["\']?', f'model: "{target_model_id}"', content)
        
        with open(config_yml_path, 'w', encoding='utf-8') as f:
            f.write(content)
            print("Successfully updated config.yml")

    # 4. Update Cline providers.json
    if os.path.exists(cline_providers_path):
        backup_file(cline_providers_path)
        
        with open(cline_providers_path, 'r', encoding='utf-8-sig') as f:
            cline_config = json.load(f)
            
        try:
            if "providers" in cline_config and "openai-compatible" in cline_config["providers"]:
                settings = cline_config["providers"]["openai-compatible"].get("settings", {})
                settings["model"] = target_model_id
                settings["baseUrl"] = "https://api.deepseek.com"
                settings["apiKey"] = target_key
                cline_config["providers"]["openai-compatible"]["settings"] = settings
                
                with open(cline_providers_path, 'w', encoding='utf-8') as f:
                    json.dump(cline_config, f, indent=2, ensure_ascii=False)
                    print("Successfully updated Cline providers.json")
        except Exception as e:
            print(f"Error updating Cline providers.json: {e}")

if __name__ == "__main__":
    main()
