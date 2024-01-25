# Geoserver with https

This repository contains a docker-compose file to spin up Geoserver, nginx, and certbot to create a geoserver instance you can access via https.

It needs some more work - in particular to remove some of the manual steps in the middle.

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

The top quarter of the file deals with standard http requests (on port 80). the rest deals with secure requests on port 443.

There is a bit of monkey patching to be done here at the moment. The https part won't work until we use certbot to validate our domain.

But that can't work without the web server up for http requests.

This also isn't smart enough to read our domain from a variable yet. So in short, we need to:

1. replace "$Domain" in 4 places with 'map.fakedomain.com'
2. remove the https part of the config file
3. run the docker compose action and some other steps
4. put the https part back in the file
5. run some other steps

For now, we need to make the file look like this:

```conf
server {
        listen 80;
        listen [::]:80;
        server_name map.fakedomain.com;

        location ~ /.well-known/acme-challenge {
          allow all;
          root /var/www/html;
        }

        location / {
                rewrite ^ https://$host$request_uri? permanent;
        }
}

```

##### Future version

**ToDo - I really want to fix this in a future version**

The todo here is making two versions of the file, possibly two versions of docker-compose, and setting it up to use the necessary bits at different steps.

There is also a job to be done to fill in the domain from an environment variable.

### Build the images

#### Note - if this is the first time

If you are not sure what you are doing at this point, or this is the first run on the server, its probably worth doing all of this but adding `--staging` after the `--no-eff-email` argument to the command line on the certbot container action.

This will do everything except get the certificates for real - so if something is wrong you'll see it.

You can only request a real certbot certificate for a domain five times in 24 hours, so while playing with config its easy to lock you out

You can view the logs for the certbot container by:

```sh
cd /usr/share/docker/geoserver-https
docker compose logs certbot
```

#### Run

`docker compose --env-file .env.production up`

On the first run, you may see this issue here: `docker: Got permission denied while trying to connect to the Docker daemon socket at unix:///var/run/docker.sock: Post http://%2Fvar%2Frun%2Fdocker.sock/v1.35/containers/create: dial unix /var/run/docker.sock: connect: permission denied. See 'docker run --help'.

If so, follow these steps to fix: <https://stackoverflow.com/questions/48957195/how-to-fix-docker-got-permission-denied-issue>`

In a second window run `docker ps` - you should see other services spinning up. This will take a minute or two.

You should be able to see logs succeeeding on certbot - you need to do this in the same folder as docker-compose, i.e:

```sh
cd /usr/share/docker/geoserver-https
docker compose logs certbot
```

### Add https back to nginx.conf

Edit `nginx-conf/nginx.conf` to look like the original version in the repository, replacing "$Domain" with map.fakedomain.com 4 times.

### Rebuild webserver

Once you have done this, destroy and recreate the webserver image without touchign anything else: `docker compose --env-file .env.production up -d --force-recreate --no-deps webserver`

### Setup geoserver reverse proxy

At this point, you should be able to access `https://map.fakedomain.com/geoserver` - but you will get an error if you try and log in <https://stackoverflow.com/questions/74755384/why-kartoza-geoserver-cant-let-me-loggin-in>.

Much earlier, we exposed port 8081 directly, to get to the geoserver insecurely.

We've done that so we can set the http_proxy_url, which should be set to <https://map.fakedomain.com/geoserver>

make sure you tick the use proxies box - you'll break the server if you don't.

That is explained in a bit more detail here <https://docs.geoserver.org/stable/en/user/configuration/globalsettings.html>

#### Future version

Per the stackoverflow link above, <https://stackoverflow.com/questions/74755384/why-kartoza-geoserver-cant-let-me-loggin-in>, this should work without the workaround of setting manually if we use the environment variables on the kartoza image (HTTP_PROXY_NAME and HTTP_SCHEME). At the timing of writing, it didn't.

It would be nice to work out how to do this without needing to go through this manual work. Either by working out why setting thoes variables did not work, or by setting this manually in the tomcat files we use below.

### Try to login

You should at this point be able to access <https://map.fakedomain.com> to login.

However, if you go to try and say add a workspace, on the save action, you'll get odd 400 errors. This is CORS rearing its ugly head. You need to tell tomcat we're not spoofing ourselves.

You can do that by editing `/usr/share/docker/geoserver-https/tomcat/webapps/geoserver/WEB-INF/web.xml`. The necessary change is explained in more detail here: <https://stackoverflow.com/questions/66526411/geoserver-advice-please-http-status-400-bad-request>

But you need to whitelist our domain and allow cross origin requests explicitly.

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

## Acknowledgements

Thanks to [@patrickleyland](<https://www.github.com/patrickleyland>), check out his New Zealand electoral mapping at [polled.co.nz](<https://www.polled.co.nz>), helping him get that up and running was the reason for pulling this all together.

## Contact

You can get in touch with me at <jake.t.clarke@gmail.com>.
