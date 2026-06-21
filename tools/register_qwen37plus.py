import os
import json
import shutil
import datetime
import re

openclaw_dir = r"C:\Users\10979\.openclaw"
openclaw_json_path = os.path.join(openclaw_dir, "openclaw.json")
auth_profiles_path = os.path.join(openclaw_dir, "auth-profiles.json")
config_yml_path = os.path.join(openclaw_dir, "config.yml")
cline_providers_path = r"C:\Users\10979\.cline\data\settings\providers.json"

timestamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")

def backup_file(path):
    if os.path.exists(path):
        backup_path = f"{path}.bak.{timestamp}"
        shutil.copy2(path, backup_path)
        print(f"Backed up {path} to {backup_path}")
        return True
    return False

def main():
    target_model = "qwen3.7-plus"
    target_provider = "openai"
    
    # Standard Aliyun MaaS base URL
    maas_base_url = "https://ws-50ggmajfpk06feuv.cn-beijing.maas.aliyuncs.com/compatible-mode/v1"
    
    # Read the openai:default key dynamically from auth-profiles.json
    maas_api_key = None
    if os.path.exists(auth_profiles_path):
        try:
            with open(auth_profiles_path, 'r', encoding='utf-8') as f:
                auth_config = json.load(f)
                maas_api_key = auth_config.get("profiles", {}).get("openai:default", {}).get("key")
        except Exception as e:
            print(f"Error reading auth-profiles.json: {e}")
            
    if not maas_api_key:
        print("Warning: Could not read openai:default API key dynamically. Using placeholder.")
        maas_api_key = "PLACEHOLDER_KEY"
    
    # 1. Update openclaw.json
    if os.path.exists(openclaw_json_path):
        backup_file(openclaw_json_path)
        
        with open(openclaw_json_path, 'r', encoding='utf-8') as f:
            config = json.load(f)
            
        # Update primary model
        if "agents" in config and "defaults" in config["agents"]:
            if "model" in config["agents"]["defaults"]:
                config["agents"]["defaults"]["model"]["primary"] = f"{target_provider}/{target_model}"
            
            if "models" not in config["agents"]["defaults"]:
                config["agents"]["defaults"]["models"] = {}
            config["agents"]["defaults"]["models"][f"{target_provider}/{target_model}"] = {}
            # Make sure downgrade model is also there
            config["agents"]["defaults"]["models"]["openai/qwen3-max-2026-01-23"] = {}
            
        # Register in models.providers.openai.models
        registered = False
        try:
            openai_models = config["models"]["providers"]["openai"]["models"]
            for model in openai_models:
                if model.get("id") == target_model:
                    registered = True
                    break
            
            if not registered:
                new_model = {
                    "id": target_model,
                    "name": target_model,
                    "reasoning": True,
                    "input": ["text", "image"],
                    "cost": {
                        "input": 0.000012,
                        "output": 0.000036,
                        "cacheRead": 0.0000024,
                        "cacheWrite": 0.000015
                    },
                    "contextWindow": 131072,
                    "contextTokens": 96000,
                    "maxTokens": 32768
                }
                openai_models.append(new_model)
                print(f"Registered {target_model} in openai models provider list.")
            else:
                print(f"{target_model} already registered in openai models provider list.")
        except KeyError as e:
            print(f"Error accessing models configuration structure: {e}")
            
        with open(openclaw_json_path, 'w', encoding='utf-8') as f:
            json.dump(config, f, indent=2, ensure_ascii=False)
            print("Successfully updated openclaw.json")

    # 2. Update config.yml
    if os.path.exists(config_yml_path):
        backup_file(config_yml_path)
        
        with open(config_yml_path, 'r', encoding='utf-8') as f:
            content = f.read()
            
        # update provider, api_key, base_url, model
        content = re.sub(r'provider:\s*["\']?[\w.-]+["\']?', f'provider: "{target_provider}"', content)
        content = re.sub(r'api_key:\s*["\']?[\w.-]+["\']?', f'api_key: "{maas_api_key}"', content)
        content = re.sub(r'base_url:\s*["\']?https?://[\w.-]+(?:/[\w.-]*)*["\']?', f'base_url: "{maas_base_url}"', content)
        content = re.sub(r'model:\s*["\']?[\w.-]+["\']?', f'model: "{target_model}"', content)
        
        with open(config_yml_path, 'w', encoding='utf-8') as f:
            f.write(content)
            print("Successfully updated config.yml")

    # 3. Update Cline providers.json
    if os.path.exists(cline_providers_path):
        backup_file(cline_providers_path)
        
        with open(cline_providers_path, 'r', encoding='utf-8') as f:
            cline_config = json.load(f)
            
        try:
            if "providers" in cline_config and "openai-compatible" in cline_config["providers"]:
                settings = cline_config["providers"]["openai-compatible"].get("settings", {})
                settings["model"] = target_model
                settings["baseUrl"] = maas_base_url
                settings["apiKey"] = maas_api_key
                cline_config["providers"]["openai-compatible"]["settings"] = settings
                
                with open(cline_providers_path, 'w', encoding='utf-8') as f:
                    json.dump(cline_config, f, indent=2, ensure_ascii=False)
                    print("Successfully updated Cline providers.json")
        except Exception as e:
            print(f"Error updating Cline providers.json: {e}")

if __name__ == "__main__":
    main()
