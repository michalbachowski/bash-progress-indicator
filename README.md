# bash-progress-indicator
A Progress Indicator (spinner) written in Bash.

Supports indicating progress for multiple tasks and tasks dependency.

# Usage

Grab the [`progress_indicator.sh`](./progress_indicator.sh) along with the [`LICENSE`](./LICENSE) file.

```bash

# load the script

source <path-to-progress_indicator.sh>

# initialize configuration
setup_progress_indicator <path-where-to-put-logs-and-status-information>

# add tasks
indicate_progress "<task-1-id>" "<task-1-display-label>" "<path-to-executable>" "<optional-space-separated-list-of-IDs-of-required-tasks>"
indicate_progress "<task-2-id>" "<task-2-display-label>" "<path-to-executable>" "<optional-space-separated-list-of-IDs-of-required-tasks>"

# run progress
start_progress_indicator
```

(see [`test_spinner.sh`](tests/test_spinner.sh) to see a real example)

* `<task-id>` can contain spaces, but be aware that the spaces will be then present in the log file names and it will be impossible to reference such task as a dependency
* `<path-to-executable`> must be an existing file that current user can execute. No additional args are allowed.
* `<optional-space-separated-list-of-IDs-of-required-tasks>` a string containing space-separated list of task IDs that need to succeede before the task is executed. \
These _parent_ tasks must be specified before can be referenced in the dependencies!

# Requirements

`Bash 4+` is required, because associative arrays are used.

# Testing

```bash
cd tests
./test_spinner.sh
```