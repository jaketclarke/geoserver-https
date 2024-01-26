
#!/bin/bash
# using export to read in the env var added a new line after any env var substitution
# for now, asking user - cannot for the life of me work out
# how to read domain from .env without it adding a new line on the substitution step

# we want the domain to go into the file in the format map.fakedomain.com
# e.g, this:
    # listen [::]:80;
    # server_name ${DOMAIN};

    # location ~ /.well-known/acme-challenge {
# becomes:
    # listen [::]:80;
    # server_name map.fakedomain.com;

    # location ~ /.well-known/acme-challenge {

# ask user
read -p 'Please enter your domain e.g. map.fakedomain.com: ' domainvar

# set env var
export DOMAIN=$domainvar

# show user
echo "Domain set to" $DOMAIN

# create staging file
envsubst < nginx-conf-staging/nginx.conf.template > nginx-conf-staging/nginx.conf

# create prod file
envsubst < nginx-conf/nginx.conf.template > nginx-conf/nginx.conf