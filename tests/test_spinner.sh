#!/usr/bin/env bash

prefix="./fixtures"

source "../progress_indicator.sh"
setup_progress_indicator ~/pi-test

indicate_progress "a" "Running a" "${prefix}/a.sh"
indicate_progress b "Installing b" "${prefix}/b.sh" a
indicate_progress c "Updating c" "${prefix}/c.sh" "a b"
indicate_progress d "Running d" "${prefix}/a.sh" a
indicate_progress e "Running e" "${prefix}/a.sh" d
indicate_progress f "Running f" "${prefix}/b.sh" b
indicate_progress g "Running g" "${prefix}/a.sh" f
indicate_progress h "Running h" "${prefix}/b.sh"
indicate_progress i "Running i" "${prefix}/c.sh"

start_progress_indicator
