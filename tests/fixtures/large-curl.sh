#!/usr/bin/env bash

# should send 30 bytes of data over 3 seconds, after a 2 seconds delay
curl -X GET "https://httpbin.org/drip?duration=3&numbytes=30&code=200&delay=2" -H "accept: application/octet-stream" -v > /dev/null
