#!/usr/bin/env bash

function send_request {
  local client_address=${1}
  local sasl_username=${2}
  export CLIENT_ADDRESS=${client_address}
  export SASL_USERNAME=${sasl_username}
  nc 127.0.0.1 10040 < <(envsubst < dev-request)
}

sleep_duration=10

for DB in ${DATABASES}; do
  # Build and run compose
  if [ "${RUN_COMPOSE}" = "1" ]; then
    docker-compose -f "dev-compose-${DB}.yml" up -d --build > /dev/null
    echo "Sleeping ${sleep_duration} seconds until compose initializes"
    sleep ${sleep_duration}
    echo "Sleep done"
  fi

  # Valid user logging in with IP addresses from Slovakia and Czech Republic
  sasl_username="valid-user@example.com"
  addresses=(5.178.48.14 31.3.32.47 46.229.224.95 46.229.230.120
             37.48.42.15 37.48.42.229 46.13.5.5
  )

  for client_address in "${addresses[@]}"; do
    send_request "$client_address" "$sasl_username" > /dev/null
  done


  # Spam user logging in with IP addresses from 7 different countries
  # SVK, CZ, IT, NOR, CAN, KAZ, FRA
  sasl_username="spam-user1@example.com"
  addresses=( 46.229.224.61
              46.13.7.27
              31.44.115.66
              79.141.110.169
              24.37.219.201
              79.142.52.15
              46.238.128.94 46.238.128.94
  )

  for client_address in "${addresses[@]}"; do
    send_request "$client_address" "$sasl_username"
  done


  # Spam user logging in with 25 different IP addresses from SVK
  sasl_username="spam-user2@example.com"
  addresses=( 213.215.64.10 213.181.128.10 213.160.160.10
              213.151.225.10 213.151.224.10 217.75.64.10
              217.75.80.10 217.118.96.10 193.87.0.10
              188.123.96.10 176.116.96.10 145.255.144.10
              94.229.32.0 93.184.64.10 91.191.64.0
              89.173.0.10 87.244.192.10 85.237.224.10
              84.245.64.10 84.16.32.10 81.162.80.10
              80.242.32.10 80.86.240.10 62.176.160.10
              62.152.224.0
  )

  for client_address in "${addresses[@]}"; do
    send_request "$client_address" "$sasl_username"
  done


  # Verify logs
  #   1. Check for rrors
  #   2. Check if spam-user exceeded country limit
  #   2. Check if spam-user exceeded IP address limit
  if docker-compose -f "dev-compose-${DB}.yml" logs postfwd-geoip-antispam \
     | grep -i "error\|fatal" \
     | grep -E -v -e "ERROR.*: Retry [123]/3 - Can't connect to MySQL server on" \
                  -e "ERROR.*: Retry [123]/3 - could not connect to server: Connection refused"; then
    echo -e 'ERROR: Errors found in log.\nTEST FAILED!'
    ERR="${ERR},1"
  fi
  if ! docker-compose -f "dev-compose-${DB}.yml" logs postfwd-geoip-antispam \
       | grep "User spam-user1@example.com was logged from more than 5 countries([67])"; then
    echo -e 'ERROR: User did not exceed country login limit (5) but should!'
    ERR="${ERR},2"
  fi
  if ! docker-compose -f "dev-compose-${DB}.yml" logs postfwd-geoip-antispam \
       | grep "User spam-user2@example.com was logged from more than 20 IP addresses(2[45])"; then
    echo -e 'ERROR: User did not exceed IP address limit (20) but should!'
    ERR="${ERR},3"
  fi

  # Cleanup
  if [ "${RUN_COMPOSE}" = "1" ]; then
    docker-compose -f "dev-compose-${DB}.yml" down > /dev/null
  fi
done

if [ -n "$ERR" ]; then
  echo "Tests ended up with errors[${ERR}]."
  exit 1
fi
