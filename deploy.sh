#!/bin/bash
set -euo pipefail

command -v terraform > /dev/null || { echo "terraform not found"; exit 1; }
command -v ansible > /dev/null ||  { echo "ansible not found"; exit 1; }

: "${AWS_ACCESS_KEY_ID:?Please set AWS_ACCESS_KEY_ID}"
: "${AWS_SECRET_ACCESS_KEY:?Please set AWS_SECRET_ACCESS_KEY}"
: "${AWS_SESSION_TOKEN:?Please set AWS_SESSION_TOKEN}"

#if DB_USER or USER_PASSWOR has not been set, the ":-" 
#operators set the value as an empty string to prevent
#set -u from crashing 

if [-z "${DB_USER:-}"]; then
    read -rp "Enter DB username: " DB_USER
fi

if [=z "${DB_PASSWORD:-}"]; then 
    read -rps "Enter DB password: " DB_PASSWORD
fi 
