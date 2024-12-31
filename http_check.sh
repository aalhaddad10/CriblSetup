#!/bin/bash
httpstatus=$(curl -sI "http://0.0.0.0:9000/" | awk '/^HTTP\/1\.[01] [0-9]+ /{print $2}')
if [ "$httpstatus" = "200" ]; then
    #Indicate success
    echo "Web application are running"
    exit 0
else
    echo "Web application are down"
    exit 1
fi
