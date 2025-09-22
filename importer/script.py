import sys
import os
import requests
import getpass
import json
import glob
import secrets
import string

TOKEN_FILE = os.path.expanduser("~/.importer_token")
TAKHTIT_UUID_FILE = os.path.expanduser("~/.importer_takhtit_uuid")

# Send the file as multipart/form-data
def send_file_to_api(file_path, api_url, token=None):
    with open(file_path, "rb") as file:
        files = {
            "file": (os.path.basename(file_path), file, "application/json")
        }
        headers = {}
        if token:
            headers["Authorization"] = f"Token {token}"
        response = requests.post(f'{api_url}/mushafs/import/', files=files, headers=headers)
        return response

def send_translation_to_api(file_path, api_url, token=None):
    with open(file_path, "rb") as file:
        files = {
            "file": (os.path.basename(file_path), file, "application/json")
        }
        headers = {}
        if token:
            headers["Authorization"] = f"Token {token}"
        response = requests.post(f'{api_url}/translations/import/', files=files, headers=headers)
        return response

def login(api_url, username=None, password=None):
    if username is None:
        username = input("Username: ")
    if password is None:
        password = getpass.getpass("Password: ")
    data = {"username": username, "password": password}
    try:
        response = requests.post(f"{api_url}/auth/login/", json=data)
        if response.status_code == 200:
            token = response.json().get("token")
            if token:
                with open(TOKEN_FILE, "w") as f:
                    f.write(token)
                print("Login successful. Token saved.")
            else:
                print("Login failed: No token in response.")
        else:
            print(f"Login failed: {response.status_code} {response.text}")
    except Exception as e:
        print(f"Login error: {e}")
        sys.exit(1)

def load_token():
    if os.path.exists(TOKEN_FILE):
        with open(TOKEN_FILE, "r") as f:
            return f.read().strip()
    return None

def save_takhtit_uuid(uuid):
    """Save takhtit UUID to file"""
    with open(TAKHTIT_UUID_FILE, "w") as f:
        f.write(uuid)

def load_takhtit_uuid():
    """Load takhtit UUID from file"""
    if os.path.exists(TAKHTIT_UUID_FILE):
        with open(TAKHTIT_UUID_FILE, "r") as f:
            return f.read().strip()
    return None

def generate_strong_password(length: int = 16) -> str:
    if length < 8:
        length = 8

    alphabet = string.ascii_letters + string.digits + "-_@#$%"
    password_chars = [
        secrets.choice(string.ascii_lowercase),
        secrets.choice(string.ascii_uppercase),
        secrets.choice(string.digits),
        secrets.choice("-_@#$%"),
    ]
    password_chars += [secrets.choice(alphabet) for _ in range(length - len(password_chars))]
    secrets.SystemRandom().shuffle(password_chars)
    return "".join(password_chars)

def create_user(api_url):
    """Create a new user and return the account UUID"""
    token = load_token()
    if not token:
        print("No token found. Please login first.")
        sys.exit(1)

    headers = {
        "Authorization": f"Token {token}",
        "accept": "application/json",
        "Content-Type": "application/json",
    }

    generated_password = generate_strong_password()
    user_payload = {
        "username": "uthmantaha",
        "password": generated_password,
        "password2": generated_password,
        "email": "user@example.com",
        "first_name": "Uthman",
        "last_name": "Taha",
    }

    try:
        resp = requests.post(f"{api_url}/users/", headers=headers, json=user_payload)
        print("Create user response:")
        print(resp.status_code, resp.text)
        if resp.status_code == 201:
            user_data = resp.json()
            account_uuid = user_data.get("uuid")
            print(f"User created successfully. UUID: {account_uuid}")
            return account_uuid
        else:
            print("Failed to create user.")
            sys.exit(1)
    except requests.exceptions.RequestException as e:
        print(f"Failed to create user: {e}")
        sys.exit(1)


def create_takhtit(api_url):
    """Create a new takhtit with a newly created user"""
    token = load_token()
    if not token:
        print("No token found. Please login first.")
        sys.exit(1)

    headers = {
        "Authorization": f"Token {token}",
        "accept": "application/json",
        "Content-Type": "application/json",
    }

    # First create a new user and get the account UUID
    account_uuid = create_user(api_url)

    try:
        resp = requests.get(f"{api_url}/mushafs/", headers=headers)
        if resp.status_code != 200:
            print(f"Failed to fetch mushafs: {resp.status_code} {resp.text}")
            sys.exit(1)
        mushafs = resp.json()
    except requests.exceptions.RequestException as e:
        print(f"Failed to fetch mushafs: {e}")
        sys.exit(1)

    hafs_uuid = None
    for mushaf in mushafs:
        if mushaf.get("short_name") == "hafs":
            hafs_uuid = mushaf.get("uuid")
            break

    if not hafs_uuid:
        print("Could not find Mushaf with short_name 'hafs'.")
        sys.exit(1)

    payload = {"mushaf_uuid": hafs_uuid, "account_uuid": account_uuid}

    try:
        response = requests.post(f"{api_url}/takhtits/", headers=headers, json=payload)
        print("Create Takhtit response:")
        print(response.status_code, response.text)
        
        if response.status_code == 201:
            takhtit_data = response.json()
            takhtit_uuid = takhtit_data.get("uuid")
            if takhtit_uuid:
                save_takhtit_uuid(takhtit_uuid)
                print(f"Takhtit created successfully. UUID: {takhtit_uuid}")
                print(f"Takhtit UUID saved to {TAKHTIT_UUID_FILE}")
            else:
                print("Takhtit created but no UUID in response.")
        else:
            print("Failed to create Takhtit.")
            sys.exit(1)
    except requests.exceptions.RequestException as e:
        print(f"Failed to create Takhtit: {e}")
        sys.exit(1)

def import_takhtit(file_path, type_name, api_url):
    token = load_token()
    if not token:
        print("No token found. Please login first.")
        sys.exit(1)

    # Load saved takhtit UUID
    uuid = load_takhtit_uuid()
    if not uuid:
        print("No takhtit UUID found. Please create a takhtit first.")
        sys.exit(1)

    if not os.path.isfile(file_path):
        print(f"File not found: {file_path}")
        sys.exit(1)

    headers = {
        "Authorization": f"Token {token}",
        "accept": "application/json",
    }

    url = f"{api_url}/takhtits/{uuid}/import/?type={type_name}"

    try:
        with open(file_path, "rb") as f:
            files = {"file": (os.path.basename(file_path), f, "application/json")}
            response = requests.post(url, headers=headers, files=files)
        
        print("Import response:")
        print(response.status_code, response.text)
        
        if response.status_code not in [200, 201]:
            print(f"Import failed with status code: {response.status_code}")
            sys.exit(1)
    except requests.exceptions.RequestException as e:
        print(f"Failed to import file: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"Error during import: {e}")
        sys.exit(1)

def main(args):
    if len(args) < 2:
        print("Usage: python script.py <command> [args...]")
        print("Commands:")
        print("  login <api_url> [username password] [--non-interactive]")
        print("  import-mushaf <input_json_file> <api_url>")
        print("  import-translations <translations_dir> <api_url>")
        print("  import-translation <input_json_file> <api_url>")
        print("  create-takhtit <api_url>")
        print("  import-takhtit <json_file> <type> <api_url>")
        sys.exit(1)

    command = args[1]

    if command == "login":
        # Check for --non-interactive flag
        if '--non-interactive' in args:
            try:
                flag_index = args.index('--non-interactive')
                # Remove the flag for easier indexing
                args_wo_flag = args[:flag_index] + args[flag_index+1:]
                if len(args_wo_flag) != 5:
                    print("Usage: python script.py login <api_url> <username> <password> --non-interactive")
                    sys.exit(1)
                api_url = args_wo_flag[2]
                username = args_wo_flag[3]
                password = args_wo_flag[4]
                login(api_url, username, password)
                return
            except Exception:
                print("Usage: python script.py login <api_url> <username> <password> --non-interactive")
                sys.exit(1)
        else:
            if len(args) == 3:
                api_url = args[2]
                login(api_url)
                return
            elif len(args) == 5:
                api_url = args[2]
                username = args[3]
                password = args[4]
                login(api_url, username, password)
                return
            else:
                print("Usage: python script.py login <api_url> [username password] [--non-interactive]")
                sys.exit(1)
    elif command == "import-mushaf":
        if len(args) != 4:
            print("Usage: python script.py import-mushaf <input_json_file> <api_url>")
            sys.exit(1)
        input_file = args[2]
        api_url = args[3]
        if not os.path.isfile(input_file):
            print(f"Error: File '{input_file}' does not exist.")
            sys.exit(1)
        if not input_file.endswith('.json'):
            print("Error: Input file must be a .json file.")
            sys.exit(1)
        token = load_token()
        try:
            response = send_file_to_api(input_file, api_url, token)
            print(f"Status code: {response.status_code}")
            if response.status_code not in [200, 201]:
                print(f"Import failed with status code: {response.status_code}")
                sys.exit(1)
            try:
                print("Response:", response.json())
            except Exception:
                print("Response (non-JSON):", response.text)
        except Exception as e:
            print(f"Failed to send file: {e}")
            sys.exit(1)
    elif command == "import-translations":
        if len(args) != 4:
            print("Usage: python script.py import-translations <translations_dir> <api_url>")
            sys.exit(1)
        translations_dir = args[2]
        api_url = args[3]
        if not os.path.isdir(translations_dir):
            print(f"Error: Directory '{translations_dir}' does not exist.")
            sys.exit(1)
        token = load_token()
        json_files = glob.glob(os.path.join(translations_dir, '*.json'))
        if not json_files:
            print(f"No .json files found in directory '{translations_dir}'.")
            sys.exit(1)
        
        success_count = 0
        failed_count = 0
        
        for file_path in json_files:
            print(f"Importing {file_path}...")
            try:
                response = send_translation_to_api(file_path, api_url, token)
                print(f"  Status code: {response.status_code}")
                if response.status_code in [200, 201]:
                    success_count += 1
                    print(f"Success")
                else:
                    failed_count += 1
                    print(f"Failed with status code: {response.status_code}")
                try:
                    print("  Response:", response.json())
                except Exception:
                    print("  Response (non-JSON):", response.text)
            except Exception as e:
                failed_count += 1
                print(f"Failed to import {file_path}: {e}")
        
        print(f"\nImport Summary: {success_count} successful, {failed_count} failed")
        if failed_count > 0:
            sys.exit(1)
    elif command == "import-translation":
        if len(args) != 4:
            print("Usage: python script.py import-translation <input_json_file> <api_url>")
            sys.exit(1)
        input_file = args[2]
        api_url = args[3]
        if not os.path.isfile(input_file):
            print(f"Error: File '{input_file}' does not exist.")
            sys.exit(1)
        if not input_file.endswith('.json'):
            print("Error: Input file must be a .json file.")
            sys.exit(1)
        token = load_token()
        try:
            response = send_translation_to_api(input_file, api_url, token)
            print(f"Status code: {response.status_code}")
            if response.status_code not in [200, 201]:
                print(f"Import failed with status code: {response.status_code}")
                sys.exit(1)
            try:
                print("Response:", response.json())
            except Exception:
                print("Response (non-JSON):", response.text)
        except Exception as e:
            print(f"Failed to send file: {e}")
            sys.exit(1)
    elif command == "create-takhtit":
        if len(args) != 3:
            print("Usage: python script.py create-takhtit <api_url>")
            sys.exit(1)
        create_takhtit(args[2])
    elif command == "import-takhtit":
        if len(args) != 5:
            print("Usage: python script.py import-takhtit <json_file> <type> <api_url>")
            sys.exit(1)
        import_takhtit(args[2], args[3], args[4])
    else:
        print(f"Unknown command: {command}")
        sys.exit(1)

if __name__ == "__main__":
    main(sys.argv)