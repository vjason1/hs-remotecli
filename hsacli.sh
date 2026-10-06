#!/usr/bin/env bash
# ==============================================================================
#
#              Copyright (C) 2016-2026 Hammerspace, Inc.
#  -----------------------------------------------------------------
#      DO NOT ATTEMPT TO LOGIN UNLESS YOU ARE AN AUTHORIZED USER.
#  -----------------------------------------------------------------
#                            _____________
#                           /             \
#                           \     _____    \
#                            \    \    \    \
#                             \    \    \    \
#                       ___    \____\    \    \
#                      /   \              \    \
#                      \    \     _____    \___/
#                       \    \    \    \
#                        \    \    \    \
#                         \    \____\    \
#                          \              \
#                           \_____________/
#
#                  Hammerspace CLI — Connection Setup
#
# ==============================================================================
#  hsacli.sh — Hammerspace CLI Remote Wrapper
#  Authors: Jason Ventresco, Shawn Dutton
#
#  VERSION HISTORY:
#    v1.0.0  Initial release. Core hsa() wrapper, credential caching via
#            HSA_IP / HSA_USER / HSA_PASS, interactive REPL mode, hsa-session,
#            hsa-status, hsa-login, hsa-logout, hsa-help.
#
#    v1.1.0  Renamed hs → hsa prefix throughout for clarity. Updated all
#            function names, prompts, and documentation to match.
#
#    v1.2.0  Added bash tab-completion via complete -F / COMPREPLY, covering
#            all Hammerspace CLI subcommands. Completion registered on source.
#
#    v1.3.0  Added Zsh tab-completion via compdef / _describe. Script now
#            auto-detects shell (bash vs zsh) and registers the appropriate
#            completion handler. Calls compinit automatically if not yet
#            initialised, removing the need for any manual zsh setup.
#
#    v1.4.0  Updated login banner and script header to use the official
#            Hammerspace logo and branding. Added author and version history.
#
#    v1.5.0  Added local hsa> mode, readline command completion inside that
#            mode, and wrapper-side -print / -recursive command chaining.
#
#    v1.6.0  Removed 'hsa <command>' prefix usage. Sourcing the script now
#            launches hsa> mode directly. All Hammerspace commands are entered
#            at the hsa> prompt without a prefix. Added Shawn Dutton as
#            co-author.
#
# ==============================================================================
#
#  USAGE — two ways to load this tool:
#
#    1) Source into your current shell (recommended):
#         source /path/to/hsacli.sh
#       Launches hsa> mode immediately. Type Hammerspace commands directly at
#       the hsa> prompt — no prefix needed. Credentials are prompted on first
#       use and cached for the session.
#
#    2) Run directly:
#         bash /path/to/hsacli.sh
#       Also drops you into hsa> mode.
#
#  USING hsa> MODE:
#
#    At the hsa> prompt, type any Hammerspace CLI command without a prefix:
#
#      hsa> share-list
#      hsa> share-list --full
#      hsa> node-list
#      hsa> share-list -print name
#      hsa> share-list -print name -recursive share-snapshot-create --share-name '$#' --now
#      hsa> share-list -export-csv shares.csv
#
#    Built-in keywords (handled locally, not sent to the cluster):
#      exit / quit    Leave hsa> mode
#      help / ?       Show the quick-reference help
#      status         Show connection info and test reachability
#      login          Re-prompt for credentials
#      logout         Clear cached credentials
#      session        Open the raw SSH Hammerspace CLI session
#
#  AVAILABLE FUNCTIONS (after sourcing):
#
#    hsa
#      Enter hsa> mode. All Hammerspace CLI commands are typed directly at the
#      hsa> prompt without any prefix.
#
#    hsa-session
#      Open a full interactive Hammerspace CLI session (SSH).
#      Use this for exploratory work or multi-step interactive tasks.
#
#    hsa-status
#      Show current connection target and whether it is reachable.
#
#    hsa-logout
#      Clear cached credentials and connection info from this shell session.
#
#    hsa-help
#      Print this usage summary.
#
#  DEPENDENCIES:
#    Required : ssh, sshpass   (sshpass handles password-based SSH auth)
#    Optional : sshpass from package manager if not present:
#                 apt install sshpass   OR   yum install sshpass
#
#  SECURITY NOTE:
#    Credentials are stored in shell environment variables (HSA_USER, HSA_IP,
#    HSA_PASS) for the duration of the shell session only. They are never
#    written to disk. The password is passed to sshpass via an environment
#    variable (SSHPASS), not on the command line, so it does not appear in
#    'ps' output. Close the terminal or run 'hsa-logout' to clear credentials.
#
#  SSH OPTIONS USED:
#    -o StrictHostKeyChecking=accept-new  Accept new host keys automatically
#                                         on first connection; reject changed
#                                         keys on subsequent connections.
#    -o ConnectTimeout=10                 Fail fast if cluster is unreachable.
#    -o LogLevel=ERROR                    Suppress SSH banner/info messages
#                                         so only HS command output reaches
#                                         stdout. Errors still show on stderr.
#    -o BatchMode=no                      Allow password auth via sshpass.
#
# ==============================================================================

# ── Colour detection ───────────────────────────────────────────────────────────
# Colours only when stdout is a TTY (terminal). Disabled automatically when
# piping output or running in non-interactive contexts.
if [ -t 1 ]; then
    _HS_RED=$'\033[0;31m'
    _HS_YEL=$'\033[1;33m'
    _HS_GRN=$'\033[0;32m'
    _HS_CYN=$'\033[0;36m'
    _HS_BLD=$'\033[1m'
    _HS_DIM=$'\033[2m'
    _HS_RST=$'\033[0m'
else
    _HS_RED=''; _HS_YEL=''; _HS_GRN=''
    _HS_CYN=''; _HS_BLD=''; _HS_DIM=''; _HS_RST=''
fi

# ── Internal helpers ───────────────────────────────────────────────────────────
_hsa_info()  { echo -e "${_HS_CYN}[hsa]${_HS_RST} $*" >&2; }
_hsa_ok()    { echo -e "${_HS_GRN}[hsa]${_HS_RST} $*" >&2; }
_hsa_warn()  { echo -e "${_HS_YEL}[hsa]${_HS_RST} $*" >&2; }
_hsa_err()   { echo -e "${_HS_RED}[hsa]${_HS_RST} $*" >&2; }


# ==============================================================================
#  CREDENTIAL SETUP
# ==============================================================================
#
#  WHAT THIS DOES:
#    Prompts for the Hammerspace cluster IP, admin username, and password.
#    Stores them in HSA_IP, HSA_USER, and HSA_PASS shell environment variables
#    for use by all hsa* functions. Variables are marked unexported to avoid
#    leaking into child processes unnecessarily.
#
#    Runs automatically when any hsa* function is first called without credentials,
#    or can be called manually at any time to change the connection target.
#
#    The password prompt uses 'read -s' (silent — no echo) and the value is
#    passed to SSH via the SSHPASS env var rather than a command-line argument,
#    so it does not appear in 'ps aux' output.
#
#    After prompting, a lightweight test connection is made (runs 'system-view'
#    non-interactively) to verify credentials before caching them.
# ==============================================================================
_hsa_setup_credentials() {
    echo
    echo "${_HS_CYN}             Copyright (C) 2016-2026 Hammerspace, Inc.${_HS_RST}"
    echo "${_HS_DIM}  ---------------------------------------------------------------${_HS_RST}"
    echo "${_HS_YEL}      DO NOT ATTEMPT TO LOGIN UNLESS YOU ARE AN AUTHORIZED USER.${_HS_RST}"
    echo "${_HS_DIM}  ---------------------------------------------------------------${_HS_RST}"
    echo "${_HS_CYN}                        _____________${_HS_RST}"
    echo "${_HS_CYN}                       /             \\${_HS_RST}"
    echo "${_HS_CYN}                       \\     _____    \\${_HS_RST}"
    echo "${_HS_CYN}                        \\    \\    \\    \\${_HS_RST}"
    echo "${_HS_CYN}                         \\    \\    \\    \\${_HS_RST}"
    echo "${_HS_CYN}                   ___    \\____\\    \\    \\${_HS_RST}"
    echo "${_HS_CYN}                  /   \\              \\    \\${_HS_RST}"
    echo "${_HS_CYN}                  \\    \\     _____    \\___/${_HS_RST}"
    echo "${_HS_CYN}                   \\    \\    \\    \\${_HS_RST}"
    echo "${_HS_CYN}                    \\    \\    \\    \\${_HS_RST}"
    echo "${_HS_CYN}                     \\    \\____\\    \\${_HS_RST}"
    echo "${_HS_CYN}                      \\              \\${_HS_RST}"
    echo "${_HS_CYN}                       \\_____________/${_HS_RST}"
    echo
    echo "${_HS_BLD}${_HS_CYN}            Hammerspace CLI — Connection Setup${_HS_RST}"
    echo
    echo -e "${_HS_DIM}  Credentials are cached in this shell session only.${_HS_RST}"
    echo -e "${_HS_DIM}  Run 'hsa-logout' to clear them. Run 'hsa-status' to review.${_HS_RST}"
    echo

    # ── Cluster IP or hostname ────────────────────────────────────────────────
    local default_ip="${HSA_IP:-}"
    if [[ -n "$default_ip" ]]; then
        printf "  Cluster IP or hostname [%s]: " "$default_ip"; read -r input_ip
        input_ip="${input_ip:-$default_ip}"
    else
        printf "  Cluster IP or hostname: "; read -r input_ip
    fi

    if [[ -z "$input_ip" ]]; then
        _hsa_err "Cluster IP is required."
        return 1
    fi

    # ── Username ──────────────────────────────────────────────────────────────
    # The HS admin account is typically 'admin' on all non-cloud platforms.
    local default_user="${HSA_USER:-admin}"
    printf "  Username [%s]: " "$default_user"; read -r input_user
    input_user="${input_user:-$default_user}"

    # ── Password (silent input) ───────────────────────────────────────────────
    printf "  Password: "; read -rs input_pass; echo  # newline after silent input

    if [[ -z "$input_pass" ]]; then
        _hsa_err "Password is required."
        return 1
    fi

    echo
    _hsa_info "Testing connection to ${input_user}@${input_ip} ..."

    # ── Dependency check ──────────────────────────────────────────────────────
    # sshpass is required to supply the password non-interactively to SSH.
    # Without it, SSH would prompt interactively, breaking scripted use.
    if ! command -v sshpass &>/dev/null; then
        _hsa_err "'sshpass' is not installed."
        _hsa_err "Install with:  apt install sshpass   OR   yum install sshpass"
        return 1
    fi

    # ── Test connection ───────────────────────────────────────────────────────
    # Run 'system-view' as a lightweight probe — it returns cluster info quickly
    # and requires valid credentials. The output is suppressed; we only care
    # about the exit code. Errors (wrong password, unreachable) still appear.
    local test_output
    test_output=$(SSHPASS="$input_pass" sshpass -e \
        ssh \
        -o StrictHostKeyChecking=accept-new \
        -o ConnectTimeout=10 \
        -o LogLevel=ERROR \
        -o BatchMode=no \
        "${input_user}@${input_ip}" \
        "system-view" 2>&1)

    local rc=$?
    if [[ $rc -ne 0 ]]; then
        _hsa_err "Connection failed (exit code ${rc})."
        _hsa_err "Check IP, username, password, and that the cluster is reachable."
        if [[ -n "$test_output" ]]; then
            _hsa_err "SSH output: ${test_output}"
        fi
        return 1
    fi

    # ── Cache credentials ─────────────────────────────────────────────────────
    # Store in shell variables. Not exported so child processes don't inherit.
    # HSA_PASS is only passed to sshpass when needed via SSHPASS= prefix.
    HSA_IP="$input_ip"
    HSA_USER="$input_user"
    HSA_PASS="$input_pass"

    _hsa_ok "Connected to ${HSA_USER}@${HSA_IP}"
    echo
}


# ==============================================================================
#  _hsa_require_credentials()
# ==============================================================================
#
#  WHAT THIS DOES:
#    Called at the start of every hsa* function that needs the cluster. If
#    credentials are not yet set (HSA_IP or HSA_PASS is empty), runs the setup
#    prompt automatically. Returns non-zero if setup fails or is aborted.
# ==============================================================================
_hsa_require_credentials() {
    if [[ -z "${HSA_IP:-}" || -z "${HSA_PASS:-}" ]]; then
        _hsa_setup_credentials || return 1
    fi
    return 0
}


# ==============================================================================
#  HSA COMMAND EXECUTION HELPERS
# ==============================================================================
#
#  HOW SSH COMMAND EXECUTION WORKS WITH THE HS RESTRICTED SHELL:
#    Normally, SSH sends a command argument directly to the remote user's shell.
#    The HS CLI is configured as the login shell for the admin user, so SSH
#    commands like:
#      ssh admin@cluster "share-list --full"
#    are received by the HS CLI as if typed at its prompt, and the output is
#    returned over the SSH channel to local stdout. The restricted shell does
#    not expose bash, so only valid HS CLI commands are accepted.
# ==============================================================================
_hsa_ssh_command() {
    local cmd="$*"

    # SSHPASS is set as an env var prefix (not a persistent export) so it is
    # visible to sshpass but not to any other process.
    SSHPASS="$HSA_PASS" sshpass -e \
        ssh \
        -o StrictHostKeyChecking=accept-new \
        -o ConnectTimeout=10 \
        -o LogLevel=ERROR \
        -o BatchMode=no \
        "${HSA_USER}@${HSA_IP}" \
        "$cmd"
}

_hsa_print_column() {
    local selector="$1"

    if ! [[ "$selector" =~ ^[0-9]+$ ]] || [[ "$selector" -lt 1 ]]; then
        _hsa_err "-print requires a column number greater than zero."
        return 1
    fi

    awk -v col="$selector" 'NF && NF >= col { print $col }'
}

_hsa_print_field() {
    local selector="$1"

    if [[ -z "$selector" ]]; then
        _hsa_err "-print requires a field name."
        return 1
    fi

    awk -v wanted="$selector" '
        function trim(s) {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
            return s
        }

        function normalize(s) {
            s = trim(tolower(s))
            gsub(/[^a-z0-9]/, "", s)
            return s
        }

        BEGIN {
            wanted = normalize(wanted)
        }

        /^[^[:space:]][^:]*:/ {
            separator = index($0, ":")
            key = substr($0, 1, separator - 1)
            value = substr($0, separator + 1)

            if (normalize(key) == wanted) {
                print trim(value)
            }
        }
    '
}

_hsa_print_values() {
    local selector="$1"

    if [[ "$selector" =~ ^[0-9]+$ ]]; then
        _hsa_print_column "$selector"
    else
        _hsa_print_field "$selector"
    fi
}

_hsa_output_to_csv() {
    awk '
        function trim(s) {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
            return s
        }

        function normalize(s) {
            s = trim(tolower(s))
            gsub(/[^a-z0-9]/, "", s)
            return s
        }

        function csv(s) {
            gsub(/"/, "\"\"", s)
            if (s ~ /[",\r\n]/) {
                return "\"" s "\""
            }
            return s
        }

        function remember_header(key, label) {
            if (!(key in header_seen)) {
                header_seen[key] = 1
                headers[++header_count] = key
                labels[key] = label
            }
        }

        function clear_current(    key) {
            for (key in current) {
                delete current[key]
            }
        }

        function flush_record(    key) {
            if (!record_has_fields) {
                return
            }
            row_count++
            for (key in current) {
                rows[row_count, key] = current[key]
            }
            clear_current()
            record_has_fields = 0
            last_key = ""
        }

        /^[[:space:]]*$/ {
            flush_record()
            next
        }

        /^[^[:space:]][^:]*:/ {
            separator = index($0, ":")
            label = trim(substr($0, 1, separator - 1))
            value = trim(substr($0, separator + 1))
            key = normalize(label)

            remember_header(key, label)
            current[key] = value
            record_has_fields = 1
            last_key = key
            next
        }

        /^[[:space:]]+/ && last_key != "" {
            continuation = trim($0)
            if (continuation != "") {
                if (current[last_key] == "") {
                    current[last_key] = continuation
                } else {
                    current[last_key] = current[last_key] " " continuation
                }
            }
            next
        }

        {
            text_line = trim($0)
            if (text_line != "" && !record_has_fields) {
                plain[++plain_count] = text_line
            }
        }

        END {
            flush_record()

            if (row_count > 0) {
                for (i = 1; i <= header_count; i++) {
                    printf "%s%s", (i == 1 ? "" : ","), csv(labels[headers[i]])
                }
                printf "\n"

                for (row = 1; row <= row_count; row++) {
                    for (i = 1; i <= header_count; i++) {
                        key = headers[i]
                        printf "%s%s", (i == 1 ? "" : ","), csv(rows[row, key])
                    }
                    printf "\n"
                }
                exit
            }

            print "Value"
            for (i = 1; i <= plain_count; i++) {
                print csv(plain[i])
            }
        }
    '
}

_hsa_export_output() {
    local export_type="$1"
    local export_file="$2"
    local output="$3"

    if [[ -z "$export_file" ]]; then
        _hsa_err "-export-${export_type} requires a local filename."
        return 1
    fi

    case "$export_type" in
        txt)
            printf '%s\n' "$output" > "$export_file" || return 1
            ;;
        csv)
            printf '%s\n' "$output" | _hsa_output_to_csv > "$export_file" || return 1
            ;;
        *)
            _hsa_err "Unknown export type: ${export_type}"
            return 1
            ;;
    esac

    _hsa_ok "Exported output to ${export_file}"
}

_hsa_substitute_recursive_value() {
    local template="$1"
    local value="$2"
    printf '%s' "${template//\$\#/$value}"
}

_hsa_run_recursive() {
    local print_selector="$1"
    local base_count="$2"
    shift 2

    local -a base_args=()
    local -a recursive_args=()
    base_args=("${@:1:base_count}")
    shift "$base_count"
    recursive_args=("$@")

    if [[ -z "$print_selector" ]]; then
        _hsa_err "-recursive requires -print <field> so the parent output has one value per child command."
        return 1
    fi

    if [[ "${#base_args[@]}" -eq 0 ]]; then
        _hsa_err "-recursive requires a parent command before -recursive."
        return 1
    fi

    if [[ "${#recursive_args[@]}" -eq 0 ]]; then
        _hsa_err "-recursive requires a child command."
        return 1
    fi

    local parent_output
    parent_output=$(_hsa_ssh_command "${base_args[@]}")
    local parent_rc=$?
    if [[ $parent_rc -ne 0 ]]; then
        return $parent_rc
    fi

    local values
    values=$(printf '%s\n' "$parent_output" | _hsa_print_values "$print_selector") || return 1

    local value
    local rc=0
    local child_rc
    local -a child_args=()
    while IFS= read -r value; do
        [[ -z "$value" ]] && continue
        child_args=()
        for arg in "${recursive_args[@]}"; do
            child_args+=("$(_hsa_substitute_recursive_value "$arg" "$value")")
        done
        _hsa_run_command "${child_args[@]}"
        child_rc=$?
        [[ $child_rc -ne 0 ]] && rc=$child_rc
    done <<< "$values"

    return $rc
}

_hsa_run_command() {
    if [[ $# -eq 0 ]]; then
        _hsa_err "No HSA command supplied."
        return 1
    fi

    local print_selector=""
    local export_type=""
    local export_file=""
    local recursive_mode=0
    local -a base_args=()
    local -a recursive_args=()
    local arg

    while [[ $# -gt 0 ]]; do
        arg="$1"
        case "$arg" in
            -print)
                shift
                if [[ $# -eq 0 ]]; then
                    _hsa_err "-print requires a field name."
                    return 1
                fi
                print_selector="$1"
                ;;
            -print=*)
                print_selector="${arg#-print=}"
                ;;
            -export-txt | export-txt)
                shift
                if [[ $# -eq 0 ]]; then
                    _hsa_err "$arg requires a local filename."
                    return 1
                fi
                export_type="txt"
                export_file="$1"
                ;;
            -export-txt=*)
                export_type="txt"
                export_file="${arg#-export-txt=}"
                ;;
            export-txt=*)
                export_type="txt"
                export_file="${arg#export-txt=}"
                ;;
            -export-csv | export-csv)
                shift
                if [[ $# -eq 0 ]]; then
                    _hsa_err "$arg requires a local filename."
                    return 1
                fi
                export_type="csv"
                export_file="$1"
                ;;
            -export-csv=*)
                export_type="csv"
                export_file="${arg#-export-csv=}"
                ;;
            export-csv=*)
                export_type="csv"
                export_file="${arg#export-csv=}"
                ;;
            -recursive)
                recursive_mode=1
                shift
                recursive_args=("$@")
                break
                ;;
            -recursive=*)
                recursive_mode=1
                recursive_args=("${arg#-recursive=}")
                shift
                recursive_args+=("$@")
                break
                ;;
            *)
                base_args+=("$arg")
                ;;
        esac
        shift
    done

    if [[ "$recursive_mode" -eq 1 ]]; then
        if [[ -n "$export_type" ]]; then
            local recursive_output
            recursive_output=$(_hsa_run_recursive "$print_selector" "${#base_args[@]}" "${base_args[@]}" "${recursive_args[@]}")
            local recursive_rc=$?
            [[ -n "$recursive_output" ]] && printf '%s\n' "$recursive_output"
            [[ $recursive_rc -ne 0 ]] && return $recursive_rc
            _hsa_export_output "$export_type" "$export_file" "$recursive_output"
            return $?
        fi

        _hsa_run_recursive "$print_selector" "${#base_args[@]}" "${base_args[@]}" "${recursive_args[@]}"
        return $?
    fi

    if [[ "${#base_args[@]}" -eq 0 ]]; then
        _hsa_err "No HSA command supplied."
        return 1
    fi

    if [[ -n "$print_selector" ]]; then
        local output
        output=$(_hsa_ssh_command "${base_args[@]}")
        local rc=$?
        [[ $rc -ne 0 ]] && return $rc
        output=$(printf '%s\n' "$output" | _hsa_print_values "$print_selector") || return 1
        printf '%s\n' "$output"
        if [[ -n "$export_type" ]]; then
            _hsa_export_output "$export_type" "$export_file" "$output"
        fi
        return $?
    fi

    if [[ -n "$export_type" ]]; then
        local output
        output=$(_hsa_ssh_command "${base_args[@]}")
        local rc=$?
        [[ -n "$output" ]] && printf '%s\n' "$output"
        [[ $rc -ne 0 ]] && return $rc
        _hsa_export_output "$export_type" "$export_file" "$output"
        return $?
    fi

    _hsa_ssh_command "${base_args[@]}"
}

# ==============================================================================
#  hsa — Enter hsa> mode
# ==============================================================================
#
#  WHAT THIS DOES:
#    Enters hsa> mode, where Hammerspace CLI commands are typed directly at the
#    prompt without any prefix. All commands are sent to the connected cluster.
#    Wrapper features (-print, -recursive, -export-txt, -export-csv) and
#    tab-completion are available at the hsa> prompt.
#
#  USAGE:
#    hsa
#
#  EXAMPLES (at the hsa> prompt):
#    hsa> share-list
#    hsa> share-list --full
#    hsa> node-list
#    hsa> share-list -print name
#    hsa> share-list -export-txt shares.txt
#    hsa> share-list -export-csv shares.csv
#    hsa> share-list -print name -recursive share-snapshot-create --share-name '$#' --now
#    hsa> system-view
#    hsa> exit
# ==============================================================================
hsa() {
    _hsa_require_credentials || return 1
    _hsa_mode
}


# ==============================================================================
#  hsa-session — Open an interactive Hammerspace CLI session
# ==============================================================================
#
#  WHAT THIS DOES:
#    Opens a full interactive SSH session to the Hammerspace cluster's restricted
#    CLI shell. Use this for exploratory work, tab-completion, and multi-step
#    interactive tasks where you want the full HS CLI experience.
#    Type 'exit' or press Ctrl-D to return to your local bash shell.
#
#    Use this for the raw remote Hammerspace CLI session. Run 'hsa' by itself
#    for local hsa> mode where wrapper features like -print and -recursive work.
# ==============================================================================
hsa-session() {
    _hsa_require_credentials || return 1
    _hsa_info "Opening interactive session to ${HSA_USER}@${HSA_IP} ..."
    _hsa_info "Type 'exit' or Ctrl-D to return to bash."
    echo
    SSHPASS="$HSA_PASS" sshpass -e \
        ssh \
        -o StrictHostKeyChecking=accept-new \
        -o ConnectTimeout=10 \
        -o LogLevel=ERROR \
        -o BatchMode=no \
        "${HSA_USER}@${HSA_IP}"
    local rc=$?
    echo
    _hsa_info "Returned to bash. HS credentials still cached (run 'hsa-logout' to clear)."
    return $rc
}


# ==============================================================================
#  hsa-status — Show current connection info and verify reachability
# ==============================================================================
#
#  WHAT THIS DOES:
#    Displays the cached connection target (IP, username) and whether the
#    cluster is currently reachable. Does not re-prompt for credentials.
#    Useful for confirming which cluster you are connected to before running
#    commands, especially when switching between clusters.
# ==============================================================================
hsa-status() {
    echo
    echo -e "${_HS_BLD}Hammerspace CLI — Connection Status${_HS_RST}"
    divider() { echo -e "${_HS_DIM}────────────────────────────────────${_HS_RST}"; }
    divider

    if [[ -z "${HSA_IP:-}" ]]; then
        echo -e "  ${_HS_YEL}Not connected.${_HS_RST} Run 'hsa-login' to connect, or run any 'hsa' command to be prompted."
        divider
        echo
        return 0
    fi

    echo -e "  Cluster  : ${_HS_BLD}${HSA_IP}${_HS_RST}"
    echo -e "  Username : ${HSA_USER}"
    echo -e "  Password : ${_HS_DIM}(cached in session — not shown)${_HS_RST}"
    echo

    # Live reachability test — run system-view and capture just the first line
    # (typically the cluster name/version) as a confirmation token.
    echo -e "  ${_HS_DIM}Testing connectivity...${_HS_RST}"
    local probe
    probe=$(SSHPASS="$HSA_PASS" sshpass -e \
        ssh \
        -o StrictHostKeyChecking=accept-new \
        -o ConnectTimeout=10 \
        -o LogLevel=ERROR \
        -o BatchMode=no \
        "${HSA_USER}@${HSA_IP}" \
        "system-view" 2>&1 | head -5)

    if [[ $? -eq 0 ]]; then
        echo -e "  ${_HS_GRN}Reachable${_HS_RST}"
        if [[ -n "$probe" ]]; then
            echo
            echo -e "${_HS_DIM}  system-view (first 5 lines):${_HS_RST}"
            while IFS= read -r line; do
                echo "    $line"
            done <<< "$probe"
        fi
    else
        echo -e "  ${_HS_RED}Unreachable${_HS_RST} — check network or run 'hsa-logout' and reconnect."
    fi

    divider
    echo
}


# ==============================================================================
#  hsa-login — Explicitly prompt for cluster credentials
# ==============================================================================
#
#  WHAT THIS DOES:
#    Prompts for the Hammerspace cluster IP/hostname, username, and password,
#    tests the connection, and caches the credentials for this shell session.
#
#    Use this at the start of a session before issuing hsa commands. If
#    credentials are already cached, re-prompts and replaces them — use it
#    to switch to a different cluster without logging out first.
#
#    Calling hsa-login explicitly is optional: credentials are also collected
#    automatically on first use of any hsa command. hsa-login is provided as
#    a clean, predictable entry point for session management.
#
#  USAGE:
#    hsa-login           # prompts interactively for IP, username, password
#
#  COMPANION:
#    hsa-logout          # clears all cached credentials
# ==============================================================================
hsa-login() {
    if [[ -n "${HSA_IP:-}" ]]; then
        _hsa_warn "Currently connected to ${HSA_USER}@${HSA_IP}."
        _hsa_warn "Entering new credentials will replace the existing connection."
        echo
    fi
    _hsa_setup_credentials
}


# ==============================================================================
#  hsa-logout — Clear cached credentials from this shell session
# ==============================================================================
#
#  WHAT THIS DOES:
#    Unsets HSA_IP, HSA_USER, and HSA_PASS from the current shell environment.
#    The next invocation of any hsa* function will prompt for credentials again.
#    Use this when switching to a different cluster or when finished with a
#    session on a shared terminal.
# ==============================================================================
hsa-logout() {
    if [[ -z "${HSA_IP:-}" ]]; then
        _hsa_info "No credentials cached — nothing to clear."
        return 0
    fi
    local old_ip="$HSA_IP"
    unset HSA_IP
    unset HSA_USER
    unset HSA_PASS
    _hsa_ok "Credentials cleared (was connected to ${old_ip})."
}


# ==============================================================================
#  hsa-help — Print usage summary
# ==============================================================================
hsa-help() {
    cat << 'HELP'

  Hammerspace CLI Wrapper — Quick Reference
  ─────────────────────────────────────────

  GETTING STARTED:
    source /path/to/hsacli.sh   Load the wrapper and enter hsa> mode
    hsa                         Re-enter hsa> mode after exiting

  hsa> BUILT-INS (handled locally, not sent to the cluster):
    exit / quit    Leave hsa> mode
    help / ?       Show this help
    status         Show connection info and test reachability
    login          Re-prompt for credentials
    logout         Clear cached credentials
    session        Open the raw SSH Hammerspace CLI session

  TAB COMPLETION:
    Tab completes command names, wrapper options, -print field names,
    recursive child commands, and local export filenames:
      hsa> sh<Tab>                    → completes toward share-* commands
      hsa> share-list -p<Tab>         → completes -print, -recursive, etc.
      hsa> share-list -print n<Tab>   → completes field names
      hsa> share-list -export-txt <Tab> → completes local filenames

  PRINT AND RECURSIVE:
    -print <field>   Extract values from record-style output like "Name: root".
                     Field matching ignores case, spaces, hyphens, underscores.
                     Numeric selectors work for whitespace-delimited output.
    -recursive       Run a child command once per extracted value.
                     Use '$#' as the placeholder. Quote it to prevent expansion.

      hsa> share-list -print name
      hsa> share-list -print name -recursive share-snapshot-create --share-name '$#' --now

  EXPORT:
    -export-txt <file>   Write exact output to a local text file.
    -export-csv <file>   Convert "Field: value" output to a local CSV file.

      hsa> share-list -export-txt shares.txt
      hsa> share-list -export-csv shares.csv
      hsa> share-list -print name -export-txt share_names.txt

  EXAMPLES:
    hsa> share-list
    hsa> share-list --full
    hsa> node-list
    hsa> share-list -print name
    hsa> share-list -export-csv shares.csv
    hsa> system-view
    hsa> share-create --name myshare --path /shares/myshare
    hsa> share-snapshot-create --share-name myshare --now

  NOTES:
    - Credentials are cached in shell env vars (HSA_IP, HSA_USER, HSA_PASS)
      for this session only. Never written to disk.
    - 'sshpass' must be installed: apt install sshpass
    - To switch clusters: run 'logout', then 'login' at the hsa> prompt.

HELP
}


# ==============================================================================
#  hsa> MODE — local prompt where the hsa prefix is implied
# ==============================================================================
#
#  WHAT THIS DOES:
#    Run 'hsa' with no arguments to enter this mode. Commands typed at hsa> are
#    sent to the Hammerspace CLI by default, so 'share-list' behaves like
#    'hsa share-list' in the normal shell.
#
#    Built-ins:
#      exit, quit          Leave hsa> mode
#      help, ?             Show hsa-help
#      status              Show connection status
#      login, logout       Change or clear credentials
#      session             Open the raw SSH Hammerspace CLI session
# ==============================================================================
_hsa_parse_line_args() {
    local line="$1"
    _HSA_PARSED_ARGS=()
    # Deliberately avoid eval here. Quotes remain in the command string that is
    # sent over SSH, while local shell substitutions are not executed by accident.
    read -r -a _HSA_PARSED_ARGS <<< "$line"
}

_HSA_PRINT_FIELDS="
    name internal-id id path lifecycle state size-limit-state export-options
    smb-browsable is-referral client-specification access-permissions
    root-squash insecure security-options
"

_hsa_line_redraw() {
    local prompt="$1"
    local chars_right=$((${#_HSA_LINE_BUFFER} - _HSA_LINE_CURSOR))

    printf '\r\033[K%s%s' "$prompt" "$_HSA_LINE_BUFFER"
    if [[ "$chars_right" -gt 0 ]]; then
        printf '\033[%dD' "$chars_right"
    fi
}

_hsa_line_current_word() {
    local start="$_HSA_LINE_CURSOR"
    local end="$_HSA_LINE_CURSOR"
    local len="${#_HSA_LINE_BUFFER}"

    while [[ "$start" -gt 0 ]]; do
        local prev="${_HSA_LINE_BUFFER:start-1:1}"
        [[ "$prev" =~ [[:space:]] ]] && break
        start=$((start - 1))
    done

    while [[ "$end" -lt "$len" ]]; do
        local next="${_HSA_LINE_BUFFER:end:1}"
        [[ "$next" =~ [[:space:]] ]] && break
        end=$((end + 1))
    done

    _HSA_WORD_START="$start"
    _HSA_WORD_END="$end"
    _HSA_CURRENT_WORD="${_HSA_LINE_BUFFER:start:end-start}"
}

_hsa_completion_words() {
    local before="${_HSA_LINE_BUFFER:0:_HSA_WORD_START}"
    local -a words_before=()
    local prev=""
    local first=""
    local word_count=0

    read -r -a words_before <<< "$before"
    word_count="${#words_before[@]}"
    if [[ "$word_count" -gt 0 ]]; then
        first="${words_before[0]}"
        prev="${words_before[word_count-1]}"
    fi

    if [[ "$word_count" -eq 0 || ( "$word_count" -eq 1 && "$first" == "hsa" ) ]]; then
        printf '%s\n' "$_HSA_COMMANDS exit quit help status login logout session hsa-session hsa-status hsa-login hsa-logout hsa-help"
        return
    fi

    if [[ "$prev" == "-print" ]]; then
        printf '%s\n' "$_HSA_PRINT_FIELDS"
        return
    fi

    if [[ "$prev" == "-recursive" ]]; then
        printf '%s\n' "$_HSA_COMMANDS"
        return
    fi

    if [[ "$prev" == "-export-txt" || "$prev" == "export-txt" || "$prev" == "-export-csv" || "$prev" == "export-csv" ]]; then
        compgen -f -- "$_HSA_CURRENT_WORD"
        return
    fi

    if [[ "$_HSA_CURRENT_WORD" == -* ]]; then
        printf '%s\n' "-print -recursive -export-txt -export-csv"
        return
    fi

    printf '%s\n' "-print -recursive -export-txt -export-csv"
}

_hsa_longest_common_prefix() {
    local prefix="$1"
    shift
    local item

    for item in "$@"; do
        while [[ -n "$prefix" && "${item:0:${#prefix}}" != "$prefix" ]]; do
            prefix="${prefix%?}"
        done
    done

    printf '%s' "$prefix"
}

_hsa_show_completion_matches() {
    local prompt="$1"
    shift

    printf '\n'
    if command -v column &>/dev/null; then
        printf '%s\n' "$@" | sort | column
    else
        printf '%s\n' "$@" | sort
    fi
    _hsa_line_redraw "$prompt"
}

_hsa_complete_line() {
    local prompt="$1"

    _hsa_line_current_word

    local cur="$_HSA_CURRENT_WORD"
    local -a matches=()
    local match
    while IFS= read -r match; do
        [[ -n "$match" ]] && matches+=("$match")
    done < <(compgen -W "$(_hsa_completion_words)" -- "$cur")

    if [[ "${#matches[@]}" -eq 0 ]]; then
        printf '\a'
        return
    fi

    local replacement=""
    if [[ "${#matches[@]}" -eq 1 ]]; then
        replacement="${matches[0]} "
    else
        replacement="$(_hsa_longest_common_prefix "${matches[@]}")"
        if [[ -z "$replacement" || "$replacement" == "$cur" ]]; then
            _hsa_show_completion_matches "$prompt" "${matches[@]}"
            return
        fi
    fi

    _HSA_LINE_BUFFER="${_HSA_LINE_BUFFER:0:_HSA_WORD_START}${replacement}${_HSA_LINE_BUFFER:_HSA_WORD_END}"
    _HSA_LINE_CURSOR=$((_HSA_WORD_START + ${#replacement}))
}

_hsa_read_line() {
    local prompt="$1"
    local char=""
    local seq=""
    local history_index="${#_HSA_MODE_HISTORY[@]}"
    local saved_buffer=""

    if [[ ! -t 0 ]]; then
        printf "%s" "$prompt"
        read -r REPLY
        return $?
    fi

    _HSA_LINE_BUFFER=""
    _HSA_LINE_CURSOR=0
    printf "%s" "$prompt"

    while IFS= read -r -s -n1 char; do
        case "$char" in
            "" | $'\r' | $'\n')
                printf '\n'
                REPLY="$_HSA_LINE_BUFFER"
                return 0
                ;;
            $'\t')
                _hsa_complete_line "$prompt"
                ;;
            $'\177' | $'\b')
                if [[ "$_HSA_LINE_CURSOR" -gt 0 ]]; then
                    _HSA_LINE_BUFFER="${_HSA_LINE_BUFFER:0:_HSA_LINE_CURSOR-1}${_HSA_LINE_BUFFER:_HSA_LINE_CURSOR}"
                    _HSA_LINE_CURSOR=$((_HSA_LINE_CURSOR - 1))
                else
                    printf '\a'
                fi
                ;;
            $'\001')
                _HSA_LINE_CURSOR=0
                ;;
            $'\005')
                _HSA_LINE_CURSOR="${#_HSA_LINE_BUFFER}"
                ;;
            $'\003')
                printf '^C\n'
                REPLY=""
                return 130
                ;;
            $'\004')
                if [[ -z "$_HSA_LINE_BUFFER" ]]; then
                    printf '\n'
                    return 1
                elif [[ "$_HSA_LINE_CURSOR" -lt "${#_HSA_LINE_BUFFER}" ]]; then
                    _HSA_LINE_BUFFER="${_HSA_LINE_BUFFER:0:_HSA_LINE_CURSOR}${_HSA_LINE_BUFFER:_HSA_LINE_CURSOR+1}"
                else
                    printf '\a'
                fi
                ;;
            $'\033')
                IFS= read -r -s -n2 seq || seq=""
                case "$seq" in
                    "[D")
                        [[ "$_HSA_LINE_CURSOR" -gt 0 ]] && _HSA_LINE_CURSOR=$((_HSA_LINE_CURSOR - 1))
                        ;;
                    "[C")
                        [[ "$_HSA_LINE_CURSOR" -lt "${#_HSA_LINE_BUFFER}" ]] && _HSA_LINE_CURSOR=$((_HSA_LINE_CURSOR + 1))
                        ;;
                    "[A")
                        if [[ "${#_HSA_MODE_HISTORY[@]}" -gt 0 && "$history_index" -gt 0 ]]; then
                            [[ "$history_index" -eq "${#_HSA_MODE_HISTORY[@]}" ]] && saved_buffer="$_HSA_LINE_BUFFER"
                            history_index=$((history_index - 1))
                            _HSA_LINE_BUFFER="${_HSA_MODE_HISTORY[history_index]}"
                            _HSA_LINE_CURSOR="${#_HSA_LINE_BUFFER}"
                        else
                            printf '\a'
                        fi
                        ;;
                    "[B")
                        if [[ "$history_index" -lt "${#_HSA_MODE_HISTORY[@]}" ]]; then
                            history_index=$((history_index + 1))
                            if [[ "$history_index" -eq "${#_HSA_MODE_HISTORY[@]}" ]]; then
                                _HSA_LINE_BUFFER="$saved_buffer"
                            else
                                _HSA_LINE_BUFFER="${_HSA_MODE_HISTORY[history_index]}"
                            fi
                            _HSA_LINE_CURSOR="${#_HSA_LINE_BUFFER}"
                        else
                            printf '\a'
                        fi
                        ;;
                esac
                ;;
            *)
                _HSA_LINE_BUFFER="${_HSA_LINE_BUFFER:0:_HSA_LINE_CURSOR}${char}${_HSA_LINE_BUFFER:_HSA_LINE_CURSOR}"
                _HSA_LINE_CURSOR=$((_HSA_LINE_CURSOR + ${#char}))
                ;;
        esac

        _hsa_line_redraw "$prompt"
    done

    return 1
}

_hsa_mode() {
    echo
    echo -e "${_HS_BLD}${_HS_CYN}Hammerspace CLI — hsa mode${_HS_RST}"
    echo -e "${_HS_DIM}Type HS commands directly. Built-ins: help, status, login, logout, session, exit.${_HS_RST}"
    echo

    _hsa_require_credentials || return 1

    local user_input
    local rc
    _HSA_MODE_HISTORY=()
    while true; do
        _hsa_read_line "hsa> "
        rc=$?
        if [[ "$rc" -eq 1 ]]; then
            _hsa_info "Leaving hsa mode."
            return 0
        elif [[ "$rc" -eq 130 ]]; then
            continue
        fi
        user_input="$REPLY"

        [[ -z "$user_input" ]] && continue
        if [[ "${#_HSA_MODE_HISTORY[@]}" -eq 0 || "${_HSA_MODE_HISTORY[${#_HSA_MODE_HISTORY[@]}-1]}" != "$user_input" ]]; then
            _HSA_MODE_HISTORY+=("$user_input")
        fi
        history -s "$user_input" 2>/dev/null || true

        case "$user_input" in
            exit | quit)
                _hsa_info "Leaving hsa mode."
                return 0
                ;;
            help | "?" | hsa-help)
                hsa-help
                continue
                ;;
            status | hsa-status)
                hsa-status
                continue
                ;;
            login | hsa-login)
                hsa-login
                continue
                ;;
            logout | hsa-logout)
                hsa-logout
                continue
                ;;
            session | hsa-session)
                hsa-session
                continue
                ;;
            hsa\ *)
                user_input="${user_input#hsa }"
                ;;
            hsa)
                hsa-session
                continue
                ;;
        esac

        _hsa_parse_line_args "$user_input"
        _hsa_run_command "${_HSA_PARSED_ARGS[@]}"
        rc=$?
        [[ $rc -ne 0 ]] && _hsa_warn "Command exited with status ${rc}"
    done

    return 0
}


# ==============================================================================
#  DIRECT-RUN MODE — activated when the script is run directly (not sourced)
# ==============================================================================
#
#  WHAT THIS DOES:
#    Kept as a compatibility wrapper for older direct-run behavior. Directly
#    running the script now enters the same hsa> mode as 'hsa' with no args, so
#    non-built-in commands are sent to the Hammerspace cluster.
# ==============================================================================
_hsa_repl() {
    _hsa_mode
}


# ==============================================================================
#  TAB COMPLETION
# ==============================================================================
#
#  WHAT THIS DOES:
#    Registers tab-completion for the 'hsa' function for both bash and zsh.
#    When the script is sourced, pressing Tab after 'hsa ' completes against
#    the full list of Hammerspace CLI commands.
#
#    Completion is context-aware:
#      hsa sh<Tab>        → completes to commands starting with "sh"
#                           (share-clone-create, share-create, share-delete, ...)
#      hsa share-<Tab>    → completes to share-* commands only
#      hsa <Tab><Tab>     → lists all available commands
#
#    The first argument completes Hammerspace commands. Later arguments complete
#    wrapper meta-options (-print, -recursive, -export-txt, -export-csv) and
#    export filenames.
#
#  SHELL SUPPORT:
#    Bash  — uses complete -F / COMPREPLY (bash 3.2+, including macOS default)
#    Zsh   — uses compdef / _arguments  (macOS Catalina+ default shell)
#            Requires compinit to have been run, which any standard zsh setup
#            (Oh My Zsh, Prezto, or a plain ~/.zshrc with 'autoload -Uz compinit
#            && compinit') will already have done.
#
#  NOTE:
#    Completion is registered only when the script is sourced into an
#    interactive shell. It has no effect when run directly as a script.
# ==============================================================================

# The shared command list — used by both bash and zsh completion handlers.
_HSA_COMMANDS="
    ad-config ad-discover
    antivirus-add antivirus-list antivirus-remove antivirus-update
    builtin-group-user-add builtin-group-user-list builtin-group-user-remove
    cluster-config
    dns-config
    domain-idmap-add domain-idmap-delete domain-idmap-list domain-idmap-reload
    dp-update
    drive-list
    email-config
    event-list event-update
    file-snapshot-create file-snapshot-delete file-snapshot-list
    file-snapshot-restore file-snapshot-schedule-list file-snapshot-update
    floating-ip-add floating-ip-remove
    gateway-list gateway-update
    gfs-participant-add gfs-participant-disable gfs-participant-enable
    gfs-participant-list gfs-participant-remove
    heartbeat-list heartbeat-send heartbeat-update
    identity-group-mapping-create identity-group-mapping-delete
    identity-group-mapping-list identity-group-mapping-update
    idp-add idp-list idp-remove idp-update
    interface-create interface-delete interface-list interface-update
    kms-add kms-list kms-remove kms-update
    label-create label-delete label-list label-update
    license-add license-list license-offline-add license-offline-cancel
    license-offline-remove license-offline-update license-remove license-update
    local-site-config
    logical-volume-create logical-volume-delete logical-volume-discover
    logical-volume-list
    login-policy-config
    metric-list
    nis-config
    node-add node-list node-mode-change node-refresh node-remove
    node-storage-repair node-update
    notification-rule-create notification-rule-list notification-rule-remove
    notification-rule-update
    ntp-config
    nvmeof-config
    object-logical-volume-discover
    object-storage-add object-storage-update
    object-volume-add object-volume-decommission object-volume-decommission-cancel
    object-volume-fail object-volume-gc-start object-volume-gc-stop
    object-volume-list object-volume-remove object-volume-remove-cancel
    object-volume-reservation-delete object-volume-set-available
    object-volume-set-unavailable object-volume-update
    objective-create objective-delete objective-export objective-import
    objective-list objective-update
    preview-no-upload-object-volume-add
    privileged-delete
    processor-add processor-list processor-remove processor-update
    remote-site-add remote-site-discover remote-site-list remote-site-remove
    remote-site-update
    role-create role-delete role-list role-update
    s3-server-bucket-create s3-server-bucket-remove
    s3-server-create s3-server-delete s3-server-list s3-server-update
    s3-server-user-add s3-server-user-remove
    schedule-create schedule-delete schedule-list schedule-update
    share-clone-create share-create share-delete share-list share-mount
    share-move share-objective-add share-objective-list share-objective-remove
    share-objective-reset share-offline share-online share-snapshot-create
    share-snapshot-delete share-snapshot-list share-snapshot-restore
    share-snapshot-schedule-list share-snapshot-update share-undelete
    share-unmount share-update
    smb-config
    snapshot-retention-create snapshot-retention-delete snapshot-retention-list
    snapshot-retention-update
    snmp-config
    software-apply software-list software-package-delete software-update-cancel
    software-update-status software-upload
    static-route-add static-route-delete static-route-list
    subnet-gateway-add subnet-gateway-delete subnet-gateway-list
    support-bundle
    syslog-config
    system-backup-config system-backup-list system-backup-restore
    system-shutdown system-view
    task-cancel task-list task-resume
    user-create user-delete user-import user-list user-password-update
    user-update
    volume-add volume-assimilation volume-assimilation-cancel
    volume-decommission volume-decommission-cancel volume-fail
    volume-group-create volume-group-delete volume-group-list
    volume-group-update volume-list volume-remove volume-remove-cancel
    volume-set-available volume-set-unavailable volume-update
"

# ── Bash completion handler ────────────────────────────────────────────────────
_hsa_completions() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local prev="${COMP_WORDS[COMP_CWORD-1]}"

    # Complete the subcommand (first argument to hsa)
    if [[ $COMP_CWORD -eq 1 ]]; then
        # shellcheck disable=SC2207
        COMPREPLY=( $(compgen -W "$_HSA_COMMANDS" -- "$cur") )
        return 0
    fi

    if [[ "$prev" == "-export-txt" || "$prev" == "export-txt" || "$prev" == "-export-csv" || "$prev" == "export-csv" ]]; then
        # shellcheck disable=SC2207
        COMPREPLY=( $(compgen -f -- "$cur") )
        return 0
    fi

    if [[ "$prev" == "-print" ]]; then
        # shellcheck disable=SC2207
        COMPREPLY=( $(compgen -W "$_HSA_PRINT_FIELDS" -- "$cur") )
        return 0
    fi

    if [[ "$prev" == "-recursive" ]]; then
        # shellcheck disable=SC2207
        COMPREPLY=( $(compgen -W "$_HSA_COMMANDS" -- "$cur") )
        return 0
    fi

    # Complete wrapper meta-options after the command name.
    # shellcheck disable=SC2207
    COMPREPLY=( $(compgen -W "-print -recursive -export-txt -export-csv" -- "$cur") )
}

# ── Zsh completion handler ─────────────────────────────────────────────────────
# Defined inside a function so it can be called after compinit has run.
# compdef is only available after compinit; this is safe to define regardless
# of shell — the zsh block below only calls it when running under zsh.
_hsa_completions_zsh() {
    local -a cmds
    # Split the shared command list into a zsh array
    cmds=( ${=_HSA_COMMANDS} )
    if (( CURRENT == 2 )); then
        # Completing the subcommand
        _describe 'hsa command' cmds
    elif [[ "${words[CURRENT-1]}" == "-export-txt" || "${words[CURRENT-1]}" == "export-txt" || "${words[CURRENT-1]}" == "-export-csv" || "${words[CURRENT-1]}" == "export-csv" ]]; then
        _files
    elif [[ "${words[CURRENT-1]}" == "-print" ]]; then
        local -a fields
        fields=( ${=_HSA_PRINT_FIELDS} )
        _describe 'hsa output field' fields
    elif [[ "${words[CURRENT-1]}" == "-recursive" ]]; then
        _describe 'hsa command' cmds
    else
        local -a opts
        opts=( -print -recursive -export-txt -export-csv )
        _describe 'hsa wrapper option' opts
    fi
}

# ==============================================================================
#  ENTRY POINT
# ==============================================================================
#
#  WHAT THIS DOES:
#    Detects whether the script is being sourced or run directly.
#
#    Sourced ('source hsacli.sh' or '. hscli.sh'):
#      All functions (hsa, hsa-session, hsa-status, hsa-logout, hsa-help) are added
#      to the current shell. No prompt is shown at source time — credentials are
#      collected on first use. Print a brief usage hint.
#
#    Run directly ('bash hsacli.sh'):
#      Launches hsa> mode.
#
#    Detection method: compare $0 (the running script name) against $BASH_SOURCE.
#    When sourced, $0 is the parent shell's name (e.g. 'bash' or '-bash').
#    When run directly, $0 matches $BASH_SOURCE[0] (the script path).
# ==============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # ── Running directly — start hsa> mode ────────────────────────────────────
    _hsa_repl
else
    # ── Being sourced — register tab completion then launch hsa> mode ─────────
    if [[ -n "${BASH_VERSION:-}" ]]; then
        # Bash: register the completion handler directly
        complete -F _hsa_completions hsa
    elif [[ -n "${ZSH_VERSION:-}" ]]; then
        # Zsh: compdef is only available after compinit has run.
        # If it isn't loaded yet, run compinit ourselves — safe to call
        # multiple times and won't conflict with a later compinit in .zshrc.
        if ! (( ${+functions[compdef]} )); then
            autoload -Uz compinit && compinit
        fi
        compdef _hsa_completions_zsh hsa
    fi

    echo -e "${_HS_CYN}[hsa]${_HS_RST} Hammerspace CLI wrapper loaded."
    echo -e "${_HS_DIM}     Type 'hsa' to enter hsa> mode. Type commands directly — no prefix needed.${_HS_RST}"
    echo -e "${_HS_DIM}     Built-ins: login  logout  status  session  help  exit${_HS_RST}"
    echo -e "${_HS_DIM}     Credentials will be prompted on first use.${_HS_RST}"

    # Launch hsa> mode immediately on source.
    hsa
fi
