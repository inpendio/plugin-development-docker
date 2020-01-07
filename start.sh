#!/bin/bash
trap stop_docker INT
function stop_docker {
	STOPPING=true
	docker-compose down
	wait $PROCESS
	exit
}

if [[ -z "$@" ]]; then
	CONTAINERS=basic-wordpress
else
	CONTAINERS="$@"
fi

echo "Starting containers:"
for CONTAINER in $CONTAINERS; do
	echo "  - $CONTAINER"
done
echo "Ensuring all containers are built"
docker-compose up --no-start $CONTAINERS

USER_ID=`id -u`
GROUP_ID=`id -g`

echo "Booting containers"
docker-compose up --detach $CONTAINERS

# First wait for the DBs to boot.
for DB_HOST in basic-database.wordpress.test woocommerce-database.wordpress.test multisite-database.wordpress.test; do
	until nc -z -v -w30 $DB_HOST 3306; do
		echo "Waiting for database connection..."
		sleep 2
	done
done

# Then install WordPress.
for CONTAINER in $CONTAINERS; do
	echo "Checking if $CONTAINER is installed!"
	docker exec -ti $CONTAINER /bin/bash -c 'wp --allow-root core is-installed'
	IS_INSTALLED=$?
	if [ $IS_INSTALLED == 1 ]; then
		echo "Installing WordPress for $CONTAINER"
		docker exec -ti $CONTAINER /bin/bash -c "usermod -u ${USER_ID} www-data"
		docker exec -ti $CONTAINER /bin/bash -c "groupmod -g ${GROUP_ID} www-data"
		docker container restart $CONTAINER
		docker exec -ti $CONTAINER /bin/bash -c 'chown -R www-data:www-data /var/www'
		docker exec --user $USER_ID -ti $CONTAINER /bin/bash -c 'php -d memory_limit=512M "$(which wp)" package install git@github.com:herregroen/wp-cli-faker.git'
		docker exec --user $USER_ID -ti $CONTAINER /bin/bash -c 'cp wp-config.php.default ../wp-config.php'
		docker cp ./seeds $CONTAINER:/seeds
		docker exec --user $USER_ID -ti $CONTAINER /seeds/$CONTAINER-seed.sh
	fi
done

# Then wait for a 200 on the homepage.
echo "Waiting for containters to boot..."
while [ "$BOOTED" != "true"  ]; do
	if curl -I http://basic.wordpress.test 2>/dev/null | grep -q "HTTP/1.1 200 OK"; then
		BOOTED=true
	else
		sleep 2
		echo "Waiting for containters to boot..."
	fi
done

open "http://basic.wordpress.test" 2>/dev/null || x-www-browser "http://basic.wordpress.test"
echo "Containers have booted! Happy developing!"
echo "Outputting logs now:"
docker-compose logs -f &
PROCESS=$!

while [ "$STOPPING" != 'true' ]; do
	CLOCK_SOURCE=`docker exec -ti basic-wordpress /bin/bash -c 'cat /sys/devices/system/clocksource/clocksource0/current_clocksource'| tr -d '[:space:]'`
	if [[ "$CLOCK_SOURCE" != 'tsc' && "$STOPPING" != 'true' ]]; then
		echo "Restarting docker now to fix out-of-sync hardware clock!"
		docker ps -q | xargs -L1 docker stop
		osascript -e 'quit app "Docker"'
		open --background -a Docker
		echo "Giving docker time to start..."
		until docker info 2> /dev/null 1> /dev/null; do
			sleep 2
			echo "Giving docker time to start..."
		done
		echo "Docker is up and running again! Booting containers!"
		docker-compose up --detach
	fi
	sleep 5
done
