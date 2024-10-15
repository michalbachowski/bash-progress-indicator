_DEBUG=0
_PI_WORK_DIR=
_PI_LOG_DIR=
_PI_STATUS_DIR=

_pi_previous_output_columns_number=0
_pi_indicator_process_pid=""
_pi_tasks=()
_pi_indicator_stopping=0
_pi_current_status_indicator_char=0
declare -A _pi_results
declare -A _pi_scripts
declare -A _pi_labels
declare -A _pi_task_pids
declare -A _pi_dependencies

_PI_STATUS_INDICATOR_CHARS=(← ↖ ↑ ↗ → ↘ ↓ ↙)
_PI_SPINNER_FRAME_NUMBER=${#_PI_STATUS_INDICATOR_CHARS[@]}

_LOG_LINES_TO_DISPLAY=4
_LOG_FILE_PATH_INFO_PREFIX="↳ "

_PI_STATUS_DONE="DONE"
_PI_STATUS_ERROR="ERROR"
_PI_STATUS_PARENT_TASK_FAILED="PARENT_TASK_FAILED"
_PI_STATUS_WAITING="WAITING"
_PI_STATUS_RUNNING="RUNNING"

_PI_STATUS_MSG_WAITING="Waiting for parent tasks to finish"
_PI_STATUS_MSG_PARENT_TASK_FAILED="Required tasks did not finish with success! Task NOT RUN!"

_PI_LINES_TO_CLEAR=0

_ECHO_CMD='echo -en'
_WHITE="\e[1;37m"
_GREEN="\e[1;32m"
_RED="\e[1;31m"
_YELLOW="\e[1;33m"
_GRAY="\e[1;90m"
_RESET_ESCAPE_SEQUENCES="\e[0m"
_CLEAR_LINE="\e[2K"
_NEWLINE="\n"
_DISABLE_LINE_WRAP="\e[?7l"
_ENABLE_LINE_WRAP="\e[?7h"
_CLEAR_DISPLAY_FROM_CURSOR_TO_END_OF_SCREEN="\e[J"

declare -A _PI_COLORS=(
    [$_PI_STATUS_WAITING]=$_WHITE
    [$_PI_STATUS_DONE]=$_GREEN
    [$_PI_STATUS_ERROR]=$_RED
    [$_PI_STATUS_PARENT_TASK_FAILED]=$_YELLOW
)

declare -A _PI_SYMBOLS=(
    [$_PI_STATUS_DONE]="✔"
    [$_PI_STATUS_ERROR]="✖"
    [$_PI_STATUS_PARENT_TASK_FAILED]="!"
    [$_PI_STATUS_WAITING]="⏸"
)

function setup_progress_indicator
{
    if [ -z "$2" ]; then
        _DEBUG="$2"
    fi
    _setup_workdir "$1"
    _setup_logdir
    _setup_statusdir

    trap _stop_progress_indicator EXIT
}

function _setup_workdir
{
    local base=""
    # base dir given explicitely
    if [ -n "$1" ]; then
        base="$1"
    # no base dir and no _PI_WORK_DIR
    elif [ -z "$_PI_WORK_DIR" ]; then
        base=/root/container_setup_logs
    # no explicit base dir given and _PI_WORK_DIR is non-empty
    else
        return
    fi

    _PI_WORK_DIR=$base/$(date +"%Y%m%d/%H%M%S")
    _log_debug "Setting up workdir to [$_PI_WORK_DIR]"

    mkdir -p $_PI_WORK_DIR
}

function _setup_logdir
{
    _setup_workdir
    if [ -z "$_PI_LOG_DIR" ] || [[ "$_PI_LOG_DIR" != "$_PI_WORK_DIR"* ]]; then
        _PI_LOG_DIR=$_PI_WORK_DIR/logs
        _log_debug "Setting up logs dir to [$_PI_LOG_DIR]"
    fi

    mkdir -p $_PI_LOG_DIR
}

function _setup_statusdir
{
    _setup_workdir
    if [ -z "$_PI_STATUS_DIR" ] || [[ "$_PI_STATUS_DIR" != "$_PI_WORK_DIR"* ]]; then
        _PI_STATUS_DIR=$_PI_WORK_DIR/statuses
        _log_debug "Setting up statuses dir to [$_PI_STATUS_DIR]"
    fi

    mkdir -p $_PI_STATUS_DIR
}

function _build_log_file_path
{
    echo -n "$_PI_LOG_DIR/$1.log"
}

function _build_status_file_path
{
    echo -n "$_PI_STATUS_DIR/$1.status"
}

function indicate_progress
{
    # Usage: indicate_progress <id> <label> <path-to-script> [<dependencies>]
    #
    # Params:
    #     id - will be used to generate eg. log or status filenames.
    #           Better to use only [a-zA-Z0-9\-_]
    #     label - text to be displayed
    #     path-to-script - where the script is located.
    #                      Script must exist and be executable.
    #     dependencies - IDs of other tasks that the task depends on.
    #                    The IDs must be defined before the script!
    #                    Dependency ID MUST NOT contain space!
    #                    This is optional.

    _validate_input "$1" "$2" "$3" "$4"

    _pi_tasks+=("$1")
    _pi_labels+=(["$1"]="$2")
    _pi_scripts+=(["$1"]="$3")
    _pi_dependencies+=(["$1"]="$4")
}

function _validate_input
{
    # ID
    if [ -z "$1" ]; then
        _error "Please provide identifier for the task."
    fi

    if [ -n "${_pi_scripts[$1]}" ]; then
        _error "The task identifier [$1] must be unique!"
    fi

    # label
    if [ -z "$2" ]; then
        _error "Please provide task label."
    fi

    # script
    if [ -z "$3" ]; then
        _error "Please provide path to the script."
    fi

    if [ ! -f "$3" ]; then
        _error "The script [$3] does not exist!"
    fi

    if [ ! -x "$3" ]; then
        _error "The script [$3] must be executable!"
    fi

    # dependencies
    if [ -n "$4" ]; then
        local dep_id=""
        for dep_id in $4; do
            if [ -z "${_pi_scripts[$dep_id]}" ]; then
                _error "The [$dep_id] dependency of the [$1] task must be defined before the [$1] task!"
            fi
        done
    fi
}

function start_progress_indicator
{
    for ((i = 0; i < ${#_pi_tasks[@]}; i++)); do
        local task_id="${_pi_tasks[$i]}"
        local script="${_pi_scripts[$task_id]}"
        local log_file="$(_build_log_file_path "$task_id")"
        local status_file="$(_build_status_file_path "$task_id")"
        local dependencies="${_pi_dependencies[$task_id]}"
        local dep_id=""

        for dep_id in $3; do
            if [ -z "${_pi_scripts[$dep_id]}" ]; then
                _error "The dependency [$dep_id] task of [$1] must be defined before the [$1] task!"
            fi
        done

        _execute_task "$script" "$log_file" "$status_file" "$dependencies"

        _pi_task_pids+=(["$task_id"]=$!)
    done

    _do_update

    if [ -z "$_pi_indicator_process_pid" ]; then
        set +m
        { _progress_updater & } 2>/dev/null
        _pi_indicator_process_pid=$!
    fi

    _wait_for_tasks_to_finish

    _stop_progress_indicator
}

function _execute_task
{
    local script="$1"
    local log_file="$2"
    local status_file="$3"
    local dependencies="$4"

    (echo $_PI_STATUS_WAITING >> "$status_file"; \
     _wait_deps "$dependencies" >> "$status_file" \
     && _execute_script_and_report_status "$script" "$log_file" >> "$status_file") &

    return $!
}

function _wait_deps
{
    local dependencies="$1"

    # do any work only when there are dependencies defined
    if [ -n "$dependencies" ]; then
        local dep_id=""
        # wait for deps
        for dep_id in $dependencies; do
            _wait_dep "${_pi_task_pids[$dep_id]}"
        done

        # check if all dependencies are done with success
        for dep_id in $dependencies; do
            _refresh_task_status "$dep_id" >> /dev/null
            dep_status="$(_read_task_status_from_file "$dep_id")"

            if _is_parent_status_failed $dep_status; then
                echo "$_PI_STATUS_PARENT_TASK_FAILED"
                return -1
            fi
        done
    fi

    echo "$_PI_STATUS_RUNNING"
    return 0
}

function _wait_dep
{
    if [ -n "$1" ]; then
        while : ; do
            ps -o pid= -p "$1" > /dev/null 2>&1
            #kill -0 "$1" > /dev/null
            if [ $? -eq 0 ]; then
                # Process is running, will check again in a moment
                sleep 1;
            else
                break
            fi
        done;
    fi
}

function _is_parent_status_failed
{
    local status="$1"

    if [ "$status" = "$_PI_STATUS_ERROR" ]; then
        return 0
    fi

    if [ "$status" = "$_PI_STATUS_PARENT_TASK_FAILED" ]; then
        return 0
    fi

    return -1
}

function _execute_script_and_report_status
{
    local script="$1"
    local log_file="$2"

    "$script" > "$log_file" 2>&1;

    if [ $? = 0 ]; then
        echo "$_PI_STATUS_DONE"
    else
        echo "$_PI_STATUS_ERROR"
    fi
}

function _wait_for_tasks_to_finish
{

    while [ $_pi_indicator_stopping -eq 0 ] ; do
        if _is_any_task_running; then
            sleep 0.2
        else
            break
        fi
    done
}

function _is_any_task_running
{
    for ((i = 0; i < ${#_pi_tasks[@]}; i++)); do
        local task_id="${_pi_tasks[$i]}"
        _refresh_task_status "$task_id"
        if _is_task_running "$task_id"; then
            return 0
        fi
    done;

    return 1
}

function _is_task_running
{
    local task_id="$1"
    local status="${_pi_results[$task_id]}"

    # no status in cache
    if [ -z "$status" ]; then
        return 0
    fi

    if [ "$status" = "$_PI_STATUS_RUNNING" ]; then
        return 0
    fi

    if [ "$status" = "$_PI_STATUS_WAITING" ]; then
        return 0
    fi

    return -1
}

function _stop_progress_indicator
{
    if [ -z "$_pi_indicator_process_pid" ]; then
        return
    fi

    { kill $_pi_indicator_process_pid && wait; } 2>/dev/null
    _pi_indicator_process_pid=""
    set -m

    _pi_indicator_stopping=1
}

function _stop_progress_updater 
{
    _pi_indicator_stopping=1

    local task_id=""
    for ((i = 0; i < ${#_pi_tasks[@]}; i++)); do
        task_id="${_pi_tasks[$i]}"

        { kill -9 "${_pi_task_pids[$task_id]}" && wait; } 2>/dev/null

    done

    _do_update
}

function _do_update
{
    local old_lines_to_clear=$_PI_LINES_TO_CLEAR
    _PI_LINES_TO_CLEAR=0
    local output=""

    _build_current_status output _PI_LINES_TO_CLEAR

    # remove any outstanding lines
    # (eg. when there were 4 log lines, and there is only 1 status line, then there will be 3 lines remaining)
    output+="${_CLEAR_DISPLAY_FROM_CURSOR_TO_END_OF_SCREEN}"

    # add empty lines if previoussly more lines were outputted than now

    # if there are any other lines to be cleared - rewind
    # the clearing itself will happen for each line separately
    # see _build_progress_info
    if [ $old_lines_to_clear -gt 0 ]; then
        $_ECHO_CMD "\e[${old_lines_to_clear}F$output${_RESET_ESCAPE_SEQUENCES}"
    else
        $_ECHO_CMD "$output${_RESET_ESCAPE_SEQUENCES}"
    fi
}

function _progress_updater
{
    trap _stop_progress_updater EXIT

    while [ $_pi_indicator_stopping = 0 ] ; do
        _do_update

        _pi_current_status_indicator_char=$(($_pi_current_status_indicator_char+1))
        if [[ $_pi_current_status_indicator_char -ge $_PI_SPINNER_FRAME_NUMBER ]]; then
            _pi_current_status_indicator_char=0
        fi
        sleep 0.1
    done
}

function _build_current_status
{
    local -n status_to_display=$1
    local -n lines_counter=$2
    for ((i = 0; i < ${#_pi_tasks[@]}; i++)); do
        local task_id="${_pi_tasks[$i]}"
        _refresh_task_status "$task_id"
        local tmp_status=""
        local lineno=0
        _build_progress_info tmp_status lineno "$task_id"
        status_to_display+="$tmp_status"
        lines_counter=$(($lines_counter+$lineno))
    done
}

function _build_progress_info
{
    local -n progress_line_to_display=$1
    local -n lines_number=$2
    local task_id="$3"
    local label="${_pi_labels[$task_id]}"
    local status="$(_get_task_status "$task_id")"
    local log_lines_number=0
    local symbol=""
    local color=""

    # show spinner only for RUNNING status
    if [ "$status" = "$_PI_STATUS_RUNNING" ]; then
        symbol="${_PI_STATUS_INDICATOR_CHARS[$_pi_current_status_indicator_char]}"
        color=$_WHITE
    else
        symbol="${_PI_SYMBOLS[$status]}"
        color="${_PI_COLORS[$status]}"
    fi

    # show logline only for tasks in the RUNNING stage
    if [ "$status" = "$_PI_STATUS_RUNNING" ]; then
        log_file="$(_build_log_file_path "$task_id")"
        raw_log_lines=$(test -f "$log_file" && tail -n "$_LOG_LINES_TO_DISPLAY" "$log_file")
    # for tasks in status ERROR, point to logs
    elif [ "$status" = "$_PI_STATUS_ERROR" ] || [ "$status" = "$_PI_STATUS_DONE" ]; then
        log_file="$(_build_log_file_path "$task_id")"
        raw_log_lines="${_LOG_FILE_PATH_INFO_PREFIX}Logs: $log_file"
    # for the WAITING status - show the info
    elif [ "$status" = "$_PI_STATUS_WAITING" ]; then
        raw_log_lines="$_PI_STATUS_MSG_WAITING"
    # for the PARENT_FAILED status - show the info
    elif [ "$status" = "$_PI_STATUS_PARENT_TASK_FAILED" ]; then
        raw_log_lines="$_PI_STATUS_MSG_PARENT_TASK_FAILED"
    fi

    _build_output_line progress_line_to_display "${color}[${symbol}] ${label}"
    _build_log_lines progress_line_to_display log_lines_number "$raw_log_lines"
    lines_number=$(($lines_number+1+$log_lines_number))
}

function _build_log_lines
{
    local -n output_lines=$1
    local -n lines_counter=$2
    local raw_lines="$3"

    local line
    while IFS= read -r line; do
        lines_counter=$(($lines_counter+1))
        _build_output_line output_lines "    ${_GRAY}${line}"
    done <<< "$raw_lines"
}

function _build_output_line
{
    local -n out=$1
    local msg_line="$2"

    out+="${_CLEAR_LINE}${_DISABLE_LINE_WRAP}${msg_line}${_ENABLE_LINE_WRAP}${_RESET_ESCAPE_SEQUENCES}${_NEWLINE}"

}

function _refresh_task_status
{
    local task_id="$1"

    if _is_task_running "$task_id"; then
        local status="$(_read_task_status_from_file "$task_id")"
        _pi_results[$task_id]="$status"
    fi
}

function _read_task_status_from_file
{
    local task_id="$1"

    local status_file="$(_build_status_file_path "$task_id")"
    local status=""

    if [ -f "$status_file" ]; then
        status="$(tail -n 1 "$status_file")"
    fi

    if [ -z "$status" ]; then
        status=$_PI_STATUS_WAITING
    fi

    echo -n "$status"
}

function _get_task_status
{
    local task_id="$1"
    local status="${_pi_results[$task_id]}"
    echo "$status"
}

function _log_debug
{
    if [ "$_DEBUG" = "1" ]; then
        echo $1 >&2
    fi
}

function _error
{
    echo $1 >&2
    exit -1
}
