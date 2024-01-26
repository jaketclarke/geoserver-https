# Geoserver with https

This repository contains a docker-compose file to spin up Geoserver, nginx, and certbot to create a geoserver instance you can access via https.

Building this has been a massive learning exercise for me, if you have any improvements, please make a PR 😊

## Assumptions

* you have set up an a record pointing at the ip address of the server we run here, through something like cloudflare. In this readme we use 'map.fakedomain.com', where map would be the name part of that record.

## Debugging

To remove all docker containers: `docker ps -aq | xargs docker stop | xargs docker rm`

To remove all docker volumes: `docker volume rm $(docker volume ls -q)`

Restart the containers using the following command: `docker-compose up -d`

To view all containers: `docker ps -aq`

To start a container `docker start container_name` - you'll see the name in the output of the previous step

## Getting Started

### Create a DigitalOcean droplet

Creating an Ubuntu 22.04 droplet, roughly following this guide <https://www.digitalocean.com/community/tutorials/initial-server-setup-with-ubuntu-18-04>

Ensure you create a non-root user and add it to the sudo group per that guide.

#### Configure firewall

Make sure to enable a firewall, but allow the traffic you want to pass. For more details, take a look at this guide: <https://www.digitalocean.com/community/tutorials/how-to-setup-a-firewall-with-ufw-on-an-ubuntu-and-debian-cloud-server>

```sh
sudo ufw allow 8081
sudo ufw allow 80
sudo ufw allow 443
sudo reboot
```

**Note**, if you are going to do something with non-public data, pay much more attention to this step, and run lots of tests at the end. This is allowing anyone on the internet to talk to the ports listed - if you are using geoserver on private data, this isn't want you want. You would want to limit your connectinos to known IP ranges for the services you are using.

#### Install docker

Get docker up and running, per this guide: <https://www.digitalocean.com/community/tutorials/how-to-install-and-use-docker-on-ubuntu-22-04>

Add a non root user, and add it to the docker group

### Get the code

#### Create a folder and set permissions

made a folder at /usr/share/docker/

set it so that all users can read write and execute - again, if you are intending to use this on any kind of shared server or put anything else on this machine, stop here and be much more thoughtful about the permission set.

```sh
sudo mkdir /usr/share/docker
sudo chown root /usr/share/docker
sudo chmod g+s /usr/share/docker
sudo chgrp -R docker /usr/share/docker
sudo chmod -R 777 /usr/share/docker
```

#### Setup git

Setup git, and set up your username and email address:

```sh
sudo apt-get install git
git config --global user.name 'Firstname Lastname'
git config --global user.email 'firstname.lastname@gmail.com'
```

Follow this guide to set up an SSH Key with GitHub. This will let the server authenticate with GitHub to access this private repo:
<https://www.theserverside.com/blog/Coffee-Talk-Java-News-Stories-and-Opinions/GitHub-SSH-Key-Setup-Config-Ubuntu-Linux>

#### Clone code

```sh
cd /usr/share/docker
git clone git@github.com:jaketclarke/geoserver-https.git
sudo chgrp -R docker geoserver-https/
sudo chmod g+s /usr/share/docker
sudo chmod -R 777 geoserver-https/
```

### Configure code

#### Setup environment variables

This will create a copy of the .env template for you: `cp .env .env.production`

You then need to fill in your real production keys. Below will open the nano text editor for you to do that. press control + x to save and exit, then hit y and enter when prompted to confirm.

#### Create an SSL Key

We will use this for configuring https later. This command will take a minute or two to run.

```sh
mkdir dhparam
sudo openssl dhparam -out dhparam/dhparam-2048.pem 2048
```

#### Set permissions on the local folders

If you look at our docker-compose.yml, we are mounting two folders in the path with our code to two volumes in two of our containers (`geoserver-data` and `nginx-conf`)

There are two lines under volumes that start with "./".

For example, in this little snippet:

```yaml
      volumes:
        - web-root:/var/www/html
        - ./nginx-conf:/etc/nginx/conf.d
```

A virtual volume is created called `web-root`, where in this container the path `/etc/nginx/conf.d` is mounted to the folder `/usr/share/docker/geoserver-https/nginx-conf`

When running docker-compose later, if these folders don't exist, they should be made. But to avoid any permissions issues, its easier to make them now and make sure we set permissions appropriately.

```sh
sudo mkdir geoserver-data
sudo chown root geoserver-data
sudo chmod g+s geoserver-data
sudo chgrp -R docker geoserver-data
sudo chmod -R 777 geoserver-data

# sudo mkdir dhparam
# we made this one in the last step
sudo chown root dhparam
sudo chmod g+s dhparam
sudo chgrp -R docker dhparam
sudo chmod -R 777 dhparam
```

#### nginx.conf

The `nginx.conf` file tells our nginx server what to do with incoming requests.

Looking at the template under [nginx.conf.template](./nginx-conf/nginx.conf.template), the top quarter of the file deals with standard http requests (on port 80). the rest deals with secure requests on port 443.

For our purposes we have two bits of complexity to deal with:

##### Variable substitution

we want to replace the palceholder `${DOMAIN}` with our map domain. To do that, run the script [make-nginx-config.sh](./make-nginx-config.sh)

```sh
make-nginx-config.sh
```

This will prompt you to enter your domain, e.g. 'map.fakedomain.com', without the quotes, or any leading or trailing spaces.

##### Versions

When we first build the images, we need to do it without HTTPS. This is because the HTTPS depends on the work the certbot image is doing for us, but that depends on the webserver being up working on HTTP.

So we first get the certbot part correct (with the `-staging` docker-compose file, and the staging nginx config file).

This is why the script above makes two sets of files, one without the HTTPS Part

### Run the staging install

Finally we are ready to get started. We first want to run the [docker-compose-staging.yaml](./docker-compose-staging.yml) build.

This uses the staging config for nginx, and it also adds `--staging` after the `--no-eff-email` argument to the command line on the certbot container action.

This will do everything except get the certificates for real. This is so we can make sure getting the certificates will work and our command has no issues. You can only request a real certbot certificate for a domain five times in 24 hours, so while playing with config its easy to lock yourself out.

We want to run:

```sh
docker compose -f docker-compose-staging.yml --env-file .env.production up
```

If you see this error:

```sh
docker: Got permission denied while trying to connect to the Docker daemon socket at unix:///var/run/docker.sock: Post http://%2Fvar%2Frun%2Fdocker.sock/v1.35/containers/create: dial unix /var/run/docker.sock: connect: permission denied. See 'docker run --help'.
```

You can fix it following [these steps](<https://stackoverflow.com/questions/48957195/how-to-fix-docker-got-permission-denied-issue>)

In a second window, we can see how this command is progressing by running

```sh
docker ps
```

After a few minutes we should see containers spinning up and doing stuff

We can view the logs for the logs for the certbot container by running:

```sh
docker compose -f docker-compose-staging.yml logs certbot
```

And the logs for for all containers by running:

```sh
docker compose -f docker-compose-staging.yml logs
```

You should be able to see logs succeeeding on certbot - you need to do this in the same folder as docker-compose, i.e:

```sh
cd /usr/share/docker/geoserver-https
docker compose logs certbot
```

### Get into Geoserver and set the proxy URL

In our [docker-compose-staging.yaml](./docker-compose-staging.yml), we've opened port 8081 to the internet for geoserver, redirecting to port 8080 locally:

```yaml
      expose:
        - 8080
        - 8443
      ports:
        - 8081:8080
      volumes:
          - geoserver-data:/opt/geoserver/data_dir
          - tomcat:/usr/local/tomcat/
```

This means we should be able to access our servers IP: 8081, e.g. `111.222.333.444:8080/geoserver`, and see the geoserver UI.

To use our domain over https later, e.g `https://map.fakedomain.com/geoserver`, we need to configure a setting called the PROXY_URL in geoserver. That's explained in more detail [here](<https://docs.geoserver.org/stable/en/user/configuration/globalsettings.html>).

You can set it through the user interface, logging in with the username and password from your `.env.production` file

You should set it to <https://map.fakedomain.com/geoserver>, making sure you tick the use proxies box.

### Run certbot for real

Rebuild the certbot image only from [docker-compose-nostaging.yaml](./docker-compose-nostaging.yml).

The only change here from [docker-compose-staging.yaml](./docker-compose-staging.yml) is removing the --staging paramter on the certbot startup command.

```sh
docker compose -f docker-compose-nostaging.yml --env-file .env.production up -d --force-recreate --no-deps certbot
```

If you run the logs for the certbot image `docker compose -f docker-compose-nostaging.yml logs certbot`, you should be able to see something like:

```text
Output
Recreating certbot ... done
Attaching to certbot
certbot      | Account registered.
certbot      | Renewing an existing certificate for your_domain and www.your_domain
certbot      |
certbot      | Successfully received certificate.
certbot      | Certificate is saved at: /etc/letsencrypt/live/your_domain/fullchain.pem
certbot      | Key is saved at:         /etc/letsencrypt/live/your_domain                               phd.com/privkey.pem
certbot      | This certificate expires on 2022-11-03.
certbot      | These files will be updated when the certificate renews.
certbot      | NEXT STEPS:
certbot      | - The certificate will need to be renewed before it expires. Cert                               bot can automatically renew the certificate in the background, but you may need                                to take steps to enable that functionality. See https://certbot.org/renewal-setu                               p for instructions.
certbot      | Saving debug log to /var/log/letsencrypt/letsencrypt.log
certbot      |
certbot      | - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -                                - - - - - - -
certbot      | If you like Certbot, please consider supporting our work by:
certbot      |  * Donating to ISRG / Let's Encrypt:   https://letsencrypt.org/do                               nate
certbot      |  * Donating to EFF:                    https://eff.org/donate-le
certbot      | - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -                                - - - - - - -
certbot exited with code 0
```

### Rebuild webserver

Once certbot is up and running, we can do the same for the webserver config that allows HTTPS.

The only change to [docker-compose.yaml](docker-compose.yml) from [docker-compose-nostaging.yaml](./docker-compose-nostaging.yml) is which nginx config is used.

```sh
docker compose -f docker-compose.yml --env-file .env.production up -d --force-recreate --no-deps webserver
```

### Rebuild geoserver

This extra step disables the 8081 port talking to geoserver.

The only relevant change to [docker-compose.yaml](docker-compose.yml) from [docker-compose-staging.yaml](./docker-compose-staging.yml) is removing that port exposure line

```sh
docker compose -f docker-compose.yml --env-file .env.production up -d --force-recreate --no-deps geoserver
```

### Setup geoserver reverse proxy

At this point, you should be able to access `https://map.fakedomain.com/geoserver` - but you will get an error if you try and log in. This is explained [here](<https://stackoverflow.com/questions/74755384/why-kartoza-geoserver-cant-let-me-loggin-in>).

### Try to login

You should at this point be able to access <https://map.fakedomain.com> to login.

However, if you go to try and say add a workspace, on the save action, you'll get 400 errors. This is CORS rearing its ugly head. You need to tell tomcat we're not spoofing ourselves.

You can do that by editing `/usr/share/docker/geoserver-https/tomcat/webapps/geoserver/WEB-INF/web.xml`. The necessary change is explained in more detail [here](<https://stackoverflow.com/questions/66526411/geoserver-advice-please-http-status-400-bad-request>).

But you need to whitelist our domain and allow cross origin requests explicitly.

You need to add this to the file:

```xml

<context-param>
     <param-name>GEOSERVER_CSRF_WHITELIST</param-name>
     <param-value>https://map.fakedomain.org/geoserver</param-value>
</context-param>

<filter>
    <filter-name>cross-origin</filter-name>
    <filter-class>org.apache.catalina.filters.CorsFilter</filter-class>
    <init-param>
        <param-name>cors.allowed.origins</param-name>
        <param-value>*</param-value>
    </init-param>
    <init-param>
        <param-name>cors.allowed.methods</param-name>
        <param-value>GET,POST,PUT,DELETE,HEAD,OPTIONS</param-value>
    </init-param>
    <init-param>
        <param-name>cors.allowed.headers</param-name>
        <param-value>*</param-value>
    </init-param>
</filter>
```

### Change the master password

Make sure you change the master password <https://gis.stackexchange.com/questions/107265/geoserver-change-master-password-masterpw-info-missing>

## Sources

This setup was largely based on this guide: <https://www.digitalocean.com/community/tutorials/how-to-secure-a-containerized-node-js-application-with-nginx-let-s-encrypt-and-docker-compose>

Understanding letsencrypt also borrowed from this guide: <https://phoenixnap.com/kb/letsencrypt-docker>

Understanding reverse proxy with ngingx borrowed from this stackoverflow answer: <https://stackoverflow.com/questions/76717951/how-to-get-a-docker-image-on-a-digitalocean-droplet-to-have-https>

## Potential improvements

### Setting PROXY_URL

Per the [stackoverflow issue linked above](<https://stackoverflow.com/questions/74755384/why-kartoza-geoserver-cant-let-me-loggin-in>), setting proxy url should be doable by setting environment variables on the kartoza geoserver image we are using (HTTP_PROXY_NAME and HTTP_SCHEME) within docker compose. At the timing of writing, this didn't work - hence this workaround of exposing port 8081 and using the UI.

## Acknowledgements

Thanks to [@patrickleyland](<https://www.github.com/patrickleyland>), check out his New Zealand electoral mapping at [polled.co.nz](<https://www.polled.co.nz>), helping him get that up and running was the reason for pulling this all together.

## Contact

You can get in touch with me at <jake.t.clarke@gmail.com>.
