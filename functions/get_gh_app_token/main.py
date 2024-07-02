import datetime
import requests
import jwt
import os

# App ID or client ID can be found: https://github.com/settings/apps/<APP NAME>
GH_APP_ID = os.environ["GH_APP_ID"]
# Installation ID can be found: https://github.com/organizations/<Organization-name>/settings/installations/<ID>
GH_APP_INSTALLATION_ID = os.environ["GH_APP_INSTALLATION_ID"]
# Private Key can be generated on: https://github.com/settings/apps/<APP NAME>
# Remember to replace newlines in the private key file with \n
GH_APP_PRI_KEY = os.environ["GH_APP_PRI_KEY"]


def get_GH_APP_token(GH_APP_ID, GH_APP_INSTALLATION_ID, GH_APP_PRI_KEY):
    now = int(datetime.datetime.now().timestamp())
    payload = {
        "iat": now - 60,
        "exp": now + 60 * 10,  # expire after 10 minutes
        "iss": GH_APP_ID,
    }
    jwt_token = jwt.encode(payload=payload, key=GH_APP_PRI_KEY, algorithm="RS256")

    # Use the JWT token to retrieve a short live token
    url = f"https://api.github.com/app/installations/{GH_APP_INSTALLATION_ID}/access_tokens"
    headers = {"Authorization": f"Bearer {jwt_token}"}
    response = requests.post(url, headers=headers)
    return response.json()["token"]


### TO-DO ###
# make this cloud function callable by providing the required inputs in webhook and return with the token
