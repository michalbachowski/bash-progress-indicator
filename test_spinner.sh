#!/usr/bin/env bash

prefix="${1:-.}"

source "$prefix/progress_indicator.sh"
setup_progress_indicator ~/pi-test

indicate_progress "a" "Running a" "${prefix}/a.sh"
indicate_progress b "Installing b" "${prefix}/b.sh" a
indicate_progress c "Updating c" "${prefix}/c.sh" "a b"
indicate_progress d "Runnig d" "${prefix}/a.sh" a
indicate_progress e "Runnig e" "${prefix}/a.sh" d
indicate_progress f "Runnig f" "${prefix}/b.sh" b
indicate_progress g "Runnig g" "${prefix}/a.sh" f
indicate_progress h "Runnig h" "${prefix}/b.sh"
indicate_progress i "Runnig i" "${prefix}/c.sh"

start_progress_indicator
