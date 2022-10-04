@echo off
REM Runs the command-line scripts documented in the README's "Azure Commands" and "Key Generation" sections
echo WARNING: These scripts will not work, unless/until you replace environmental variable values in one step with the results from previous steps.
az account list > subscriptions.json
az ad sp create-for-rbac --skip-assignment --name my-service-principal > ad_sp.json
az role assignment create --assignee %SP_ID% --scope "/subscriptions/%SUBSCRIPTION_ID%" --role Contributor > role_assignment.json
ssh-keygen -t rsa -b 4096 -f ".\id_rsa" -N ""
