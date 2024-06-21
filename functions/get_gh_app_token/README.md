# functions/get_gh_app_token
An example for retrieving a short-live token for a GitHub App 

## Input

### GH_APP_ID
App ID can be found: https://github.com/settings/apps/\<APP NAME>

Or by going to `GitHub Settings` >  `Developer settings` > `GitHub Apps` > *Your app* > `App ID`

### GH_APP_INSTALLATION_ID
Installation ID can be found by going to `GitHub Settings` >  `Integrations` > `Applications` > *Your app* 

The installation ID will be in the URL of the page you are on

https://github.com/organizations/\<Organization-name>/settings/installations/\<ID>

or 

https://github.com/settings/installations/\<ID>

### GH_APP_PRI_KEY
Private Key can be generated: https://github.com/settings/apps/\<APP NAME>

Or by going to `GitHub Settings` >  `Developer settings` > `GitHub Apps` > *Your app* > `Private Key`

Remember to replace newlines in the private key file with `\n` and provide this as a string variable

## Output
A short-live (10 min) token will be printed