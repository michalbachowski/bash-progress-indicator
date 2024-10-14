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

_PI_STATUS_DONE="DONE"
_PI_STATUS_ERROR="ERROR"
_PI_STATUS_PARENT_TASK_FAILED="PARENT_TASK_FAILED"
_PI_STATUS_WAITING="WAITING"
_PI_STATUS_RUNNING="RUNNING"

_PI_STATUS_MSG_WAITING="Waiting for parent tasks to finish"
_PI_STATUS_MSG_PARENT_TASK_FAILED="Required tasks did not finish with success! Task NOT RUN!"

_WHITE="\e[1;37m"
_GREEN="\e[1;32m"
_RED="\e[1;31m"
_YELLOW="\e[1;33m"
_RESET_COLOR="\e[0;0m"
_CLEAR_LINE="\e[2K"
_NEWLINE="\n"
_DISABLE_LINE_WRAP="\033[?7l"

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

    trap _reset_indicator EXIT
}

function _setup_workdir
{
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
        task_id="${_pi_tasks[$i]}"
        script="${_pi_scripts[$task_id]}"
        log_file="$(_build_log_file_path "$task_id")"
        status_file="$(_build_status_file_path "$task_id")"
        dependencies="${_pi_dependencies[$task_id]}"

        for dep_id in $3; do
            if [ -z "${_pi_scripts[$dep_id]}" ]; then
                _error "The dependency [$dep_id] task of [$1] must be defined before the [$1] task!"
            fi
        done

        _execute_task "$script" "$log_file" "$status_file" "$dependencies"

        _pi_task_pids+=(["$task_id"]=$!)
    done

    _display_current_status

    if [ -z "$_pi_indicator_process_pid" ]; then
        set +m
        { _indicate_progress & } 2>/dev/null
        _pi_indicator_process_pid=$!
    fi

    _wait_for_tasks_to_finish

    _reset_indicator
}

function _execute_task
{
    script="$1"
    log_file="$2"
    status_file="$3"
    dependencies="$4"

    (echo $_PI_STATUS_WAITING >> "$status_file"; \
     _wait_deps "$dependencies" >> "$status_file" \
     && _execute_script_and_report_status "$script" "$log_file" >> "$status_file") &

    return $!
}

function _wait_deps
{
    dependencies="$1"

    # do any work only when there are dependencies defined
    if [ -n "$dependencies" ]; then
        # wait for deps
        for dep_id in $dependencies; do
            _wait_dep "${_pi_task_pids[$dep_id]}"
        done

        # check is all dependencies are done with success
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
    test -n "$1" && while [ -e "/proc/${1}" ]; do sleep 1; done;
}

function _is_parent_status_failed
{
    status="$1"

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
    script="$1"
    log_file="$2"

    "$script" > "$log_file" 2>&1;

    if [ $? = 0 ]; then
        echo "$_PI_STATUS_DONE"
    else
        echo "$_PI_STATUS_ERROR"
    fi
}

function _wait_for_tasks_to_finish
{

    while [ $_pi_indicator_stopping = 0 ] ; do
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
        task_id="${_pi_tasks[$i]}"
        _refresh_task_status "$task_id"
        if _is_task_running "$task_id"; then
            return 0
        fi
    done;

    return 1
}

function _is_task_running
{
    task_id="$1"
    status="${_pi_results[$task_id]}"

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

function _reset_indicator
{
    if [ -z "$_pi_indicator_process_pid" ]; then
        return
    fi

    { kill $_pi_indicator_process_pid && wait; } 2>/dev/null
    _pi_indicator_process_pid=""
    set -m
    echo -en "\033[2K\r"

    _pi_indicator_stopping=1
#tail -n +1 $_PI_LOG_DIR/*.done
#tail -n +1 $_PI_STATUS_DIR/*
#cat done.done
}

function _shutdown_progress_indicator
{
    _pi_indicator_stopping=1

    for ((i = 0; i < ${#_pi_tasks[@]}; i++)); do
        task_id="${_pi_tasks[$i]}"

        { kill -9 "${_pi_task_pids[$task_id]}" && wait; } 2>/dev/null

    done

    _do_update
}

function _do_update
{
    _display_current_status "clear"
}

function _display_current_status
{
    clear="$1"

    out=""
    _build_current_status out

    if [ -n "$clear" ]; then
        # if there are any other lines to be cleared - rewind
        # the clearing itself will happen for each line separately
        # see _build_progress_line
        lines=$((${#_pi_tasks[@]}*2))
        echo -en "\e[${lines}F$out"
    else
        echo -en "$out"
    fi
}

function _indicate_progress
{
    trap _shutdown_progress_indicator EXIT

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
    for ((i = 0; i < ${#_pi_tasks[@]}; i++)); do
        task_id="${_pi_tasks[$i]}"
        _refresh_task_status "$task_id"
        tmp=""
        _build_progress_line tmp "$task_id"
        status_to_display+="$tmp"
    done
}

function _build_progress_line
{
    local -n progress_line_to_display=$1
    task_id="$2"
    label="${_pi_labels[$task_id]}"
    status="$(_get_task_status "$task_id")"
    log_line=""

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
        log_line="${_DISABLE_LINE_WRAP}↳ $(test -f "$log_file" && tail -n 1 "$log_file")"
    # for tasks in status ERROR, point to logs
    elif [ "$status" = "$_PI_STATUS_ERROR" ] || [ "$status" = "$_PI_STATUS_DONE" ]; then
        log_file="$(_build_log_file_path "$task_id")"
        log_line="↳ Logs: $log_file"
    # for the WAITING status - show the info
    elif [ "$status" = "$_PI_STATUS_WAITING" ]; then
        log_line="$_PI_STATUS_MSG_WAITING"
    # for the PARENT_FAILED status - show the info
    elif [ "$status" = "$_PI_STATUS_PARENT_TASK_FAILED" ]; then
        log_line="$_PI_STATUS_MSG_PARENT_TASK_FAILED"
    fi

    progress_line_to_display="${_CLEAR_LINE}${color}[$symbol] $label ${_RESET_COLOR}${_NEWLINE}${_CLEAR_LINE}    $log_line${_NEWLINE}"
}

function _refresh_task_status
{
    task_id="$1"

    if _is_task_running "$task_id"; then
        status="$(_read_task_status_from_file "$task_id")"
        _pi_results[$task_id]="$status"
    fi
}

function _read_task_status_from_file
{
    task_id="$1"

    status_file="$(_build_status_file_path "$task_id")"
    status=""

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
    task_id="$1"
    status="${_pi_results[$task_id]}"
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
