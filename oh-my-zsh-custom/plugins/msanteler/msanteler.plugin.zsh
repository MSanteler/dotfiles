alias kctx="kubectx"
alias kns="kubens"
alias kb="kubie"
alias kbb="kubie ctx && kubie ns"

# Alias to list all functions using fzf
alias listfuncs="typeset -f | grep '()' | awk '{print $1}' | fzf"

alias staging_diff="git log --pretty=oneline origin/staging..origin/master | cat"

GLOBALIAS_FILTER_VALUES=(restish grep ls '*')

# Standarized $0 handling
# https://zdharma-continuum.github.io/Zsh-100-Commits-Club/Zsh-Plugin-Standard.html
0="${${ZERO:-${0:#$ZSH_ARGZERO}}:-${(%):-%N}}"
0="${${(M)0:#/*}:-$PWD/$0}"

precmd() {
  set_env_based_on_git_remote
}

function prompt_month_icon() {
    local current_date=$(date +%m-%d)
    local month=$(date +%m)

    # Associative array for specific date emojis
    local -A date_emojis
    date_emojis=(
        01-01 "🎆"      # New Year's Day
        03-05 "💍"      # Your Wedding Anniversary
        07-04 "🇺🇸"      # Independence Day
        10-26 "🎂"      # My Birthday
        10-31 "👻"      # Halloween
        11-11 "🌺"      # Veterans Day
        11-28 "🦃"      # Thanksgiving (this date can vary)
        12-25 "🎄"      # Christmas Day
        # ... (you can add more special dates and emojis here)
    )

    # If today is a special date, display its emoji
    if [[ -n $date_emojis[$current_date] ]]; then
        local icon=$date_emojis[$current_date]
    else
        # Two-dimensional array of emojis for each month
        local -A month_emojis
        month_emojis=(
        01 "❄️ ☃️ 🌨 🧥 🧣"
        02 "❤️ 💖 💌 🌹 🍫"
        03 "🌬 🌦 🌈 🍀 ☘️"
        04 "☔️ 🌱 🌸 🌷 🦋"
        05 "💐 🌻 🌺 🌾 🌼"
        06 "🌞 🍓 🍉 🦜 🌻"
        07 "🏖️ 🍦 ⛱️ 🚤 🌅"
        08 "🍎 🌽 🍑 🍅 🌾"
        09 "🍁 🍂 🍃 🌰 🥾"
        10 "🎃 🕸 🦇 🍁 🍂"
        11 "🍠 🍁 🌽 🍂 🍎"
        12 "🎅 🕯 🎁 🌟 ❄️"
        )

        # Splitting the month's emoji string into an array and randomly selecting one emoji
        local current_month_emojis=(${(s: :)month_emojis[$month]})
        icon=${current_month_emojis[$(( $RANDOM % ${#current_month_emojis[@]} + 1 ))]}
    fi

    p10k segment -b 6 -f 0 -i $icon -t 'hello, %n'
}

# Function to control GitHub workflows
toggle_gha_workflows() {
    # If the user provides the '-h' or '--help' flag, display the help message
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: toggle_workflows [disable|enable]"
        echo "Enable or disable GitHub Actions by renaming workflow files."
        echo ""
        echo "Options:"
        echo "  disable: Rename all .yml files in .github/workflows to .disabled"
        echo "  enable : Rename all .disabled files in .github/workflows back to .yml"
        echo ""
        echo "Example:"
        echo "  toggle_workflows disable   # Disables all workflows"
        echo "  toggle_workflows enable    # Enables all workflows"
        return 0
    fi

    local action=$1
    local dir=".github/workflows"

    if [[ ! -d "$dir" ]]; then
        echo "Directory $dir not found. Are you in the right project?"
        return 1
    fi

    case $action in
        disable)
            for file in "$dir"/*.yml; do
                [ -f "$file" ] && mv "$file" "${file%.yml}.disabled"
            done
            ;;
        enable)
            for file in "$dir"/*.disabled; do
                [ -f "$file" ] && mv "$file" "${file%.disabled}"
            done
            ;;
        *)
            echo "Unknown action. Use 'disable' or 'enable'."
            return 1
            ;;
    esac
}

# Dumps dns records for the relevant zones
find_aws_dns_records() {
    # If the user provides the '-h' or '--help' flag, display the help message
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: find_dns_records [fuzzy_record_match] [fuzzy_zone_match]"
        echo "Search AWS Route53 for DNS records based on fuzzy search parameters."
        echo ""
        echo "If fuzzy_record_match is omitted, the current Kubernetes namespace is used."
        echo "If fuzzy_zone_match is omitted, the current Kubernetes context is used."
        echo ""
        echo "Examples:"
        echo "  find_dns_records            # Uses current k8s namespace and context"
        echo "  find_dns_records myrecord   # Searches for 'myrecord' in the current k8s context"
        echo "  find_dns_records myrecord myzone.com.   # Explicit search for 'myrecord' in 'myzone.com.'"
        return 0
    fi

    # Get the current Kubernetes context and namespace
    local default_zone_match=$(kubectl config current-context)
    local default_record_match=$(kubectl config view --minify --output 'jsonpath={..namespace}')
    
    # If namespace retrieval is empty, default to "default"
    if [ -z "$default_record_match" ]; then
        default_record_match="default"
    fi

    # Set default arguments based on provided inputs
    local fuzzy_record_match=${1:-$default_record_match}
    local fuzzy_zone_match=${2:-$default_zone_match}

    # Fetch the ID of the first hosted zone that matches the provided name
    local zone_id=$(aws route53 list-hosted-zones | jq -r --arg name "$fuzzy_zone_match" '.HostedZones[] | select(.Name | contains($name)) | .Id' | head -1)

    # If we couldn't find the zone, exit
    if [ -z "$zone_id" ]; then
        echo "Couldn't find a matching hosted zone for: $fuzzy_zone_match"
        return 1
    fi

    # Fetch and filter record sets based on the provided record name
    aws route53 list-resource-record-sets --hosted-zone-id "$zone_id" | jq --arg name "$fuzzy_record_match" '.ResourceRecordSets[] | select(.Name | contains($name))'
}

set_env_based_on_git_remote() {
    # Check if the current directory is a git repository
    if git rev-parse --is-inside-work-tree &>/dev/null; then
        # Fetch the URL of the 'origin' remote
        local remote_url=$(git config --get remote.origin.url)

        # Check the pattern of the remote URL to match git@github.com:myaccount/...
        if [[ "$remote_url" == "git@github.com:MSanteler/"* ]]; then
            export GIT_SSH_COMMAND="ssh -i /Users/msanteler-clearstep/.ssh/ms_github -o IdentitiesOnly=yes"
        else
            # Optionally, unset the environment variable if not in the desired directory
            unset GIT_SSH_COMMAND
        fi
    else
        # If not inside a git repo, optionally unset the variable
        unset GIT_SSH_COMMAND
    fi
}

# Kubernetes helper functions:
# Exec into a pod
kube-exec() {
    if [[ "$1" == "--help" ]]; then
        echo "Usage: kube-exec"
        echo "Exec into a Kubernetes pod."
        return 0
    fi

    local pod_name container_name cmd_choice custom_cmd command

    pod_name=$(kubectl get pods --no-headers=true | awk '{print $1}' | fzf --prompt="Select a pod to exec into: ")
    [[ -z "$pod_name" ]] && echo "No pod selected." && return 1

    container_name=$(kubectl get pods "$pod_name" -o=jsonpath='{.spec.containers[*].name}' | tr ' ' '\n' | fzf --prompt="Select a container: ")

    cmd_choice=$(echo -e "bash\nsh\ncustom" | fzf --prompt="Select a command to run inside the pod: ")

    case $cmd_choice in
    bash)
        custom_cmd="/bin/bash"
        ;;
    sh)
        custom_cmd="/bin/sh"
        ;;
    custom)
        echo -n "Enter your custom command: "
        read custom_cmd
        ;;
    *)
        echo "Invalid command choice."
        return 1
        ;;
    esac

    command="kubectl exec -it $pod_name"
    [[ -n "$container_name" ]] && command="$command -c $container_name"

    echo "Executing: $command -- $custom_cmd"
    eval "$command -- $custom_cmd"
}

# Display logs for a pod
kube-logs() {
    if [[ "$1" == "--help" ]]; then
        echo "Usage: kube-logs"
        echo "Fetch logs from a Kubernetes pod."
        return 0
    fi

    local pod_name command

    pod_name=$(kubectl get pods --no-headers=true | awk '{print $1}' | fzf --prompt="Select a pod to fetch logs from: ")

    [[ -z "$pod_name" ]] && echo "No pod selected." && return 1

    command="kubectl logs $pod_name"

    echo "Executing: $command"
    eval "$command"
}

# Describe a pod
kube-describe() {
    if [[ "$1" == "--help" ]]; then
        echo "Usage: kube-describe"
        echo "Describe a Kubernetes pod."
        return 0
    fi

    local pod_name command

    pod_name=$(kubectl get pods --no-headers=true | awk '{print $1}' | fzf --prompt="Select a pod to describe: ")

    [[ -z "$pod_name" ]] && echo "No pod selected." && return 1

    command="kubecolor describe pod $pod_name"

    echo "Executing: $command"
    eval "$command"
}

# Delete a pod
kube-delete() {
    if [[ "$1" == "--help" ]]; then
        echo "Usage: kube-delete"
        echo "Delete a Kubernetes pod."
        return 0
    fi

    local pod_name command

    pod_name=$(kubectl get pods --no-headers=true | awk '{print $1}' | fzf --prompt="Select a pod to delete: ")

    [[ -z "$pod_name" ]] && echo "No pod selected." && return 1

    command="kubectl delete pod $pod_name"

    echo "About to execute: $command"
    echo -n "Are you sure? [y/N] "
    read answer
    if [[ "$answer" == "y" || "$answer" == "Y" ]]; then
        echo "Executing: $command"
        eval "$command"
    else
        echo "Pod deletion aborted."
    fi
}

kube-debug() {
    # Help documentation for kube-debug.
    if [[ "$1" == "--help" ]]; then
        echo "Usage: kube-debug"
        echo "Run a debug container for a Kubernetes pod. Offers a choice between debugging styles and images."
        return 0
    fi

    # This function provides interactive debugging for a Kubernetes pod.
    local pod_name debug_style image_choice custom_image container_name

    # Get the pod name using fzf.
    pod_name=$(kubectl get pods --no-headers=true | awk '{print $1}' | fzf --prompt="Select a pod: ")

    # Exit if no pod name is provided or selected.
    [[ -z "$pod_name" ]] && echo "No pod selected." && return 1

    # Prompt for the debug style using fzf.
    debug_style=$(echo "--target\n--share-processes" | fzf --prompt="Choose a debug style: ")

    # Exit if no debug style is selected.
    [[ -z "$debug_style" ]] && echo "No debug style selected." && return 1

    # If --target is selected, get the container name.
    if [[ "$debug_style" == "--target" ]]; then
        container_name=$(kubectl get pods "$pod_name" -o=jsonpath='{.spec.containers[*].name}' | tr ' ' '\n' | fzf --prompt="Select a container: ")
        [[ -z "$container_name" ]] && echo "No container selected." && return 1
    fi

    # Prompt for the image choice using fzf.
    image_choice=$(echo -e "busybox\nalpine\ndebian\ncustom" | fzf --prompt="Choose a debug image: ")

    # Exit if no image choice is selected.
    [[ -z "$image_choice" ]] && echo "No image selected." && return 1

    # If custom image is chosen, prompt the user for the custom image name.
    if [[ "$image_choice" == "custom" ]]; then
        print -n "Enter the custom image: "
        read custom_image
        image_choice="$custom_image"
    fi

    # Construct and execute the kubectl debug command based on chosen options.
    local command
    if [[ "$debug_style" == "--target" ]]; then
        command="kubectl debug -it --target $container_name $pod_name --image=$image_choice"
    else
        command="kubectl debug -it $pod_name --share-processes --image=$image_choice"
    fi

    # Print and execute the command.
    echo "Executing: $command"
    eval "$command"
}

kube-cp() {
  if [[ "$1" == "--help" ]]; then
      echo "Usage: kube-cp"
      echo "Copy files to or from a Kubernetes pod."
      return 0
  fi

  local pod_name container_name src dest action_choice command

  pod_name=$(kubectl get pods --no-headers=true | awk '{print $1}' | fzf --prompt="Select a pod: ")
  [[ -z "$pod_name" ]] && echo "No pod selected." && return 1

  container_name=$(kubectl get pods "$pod_name" -o=jsonpath='{.spec.containers[*].name}' | tr ' ' '\n' | fzf --prompt="Select a container: ")

  action_choice=$(echo -e "to_pod\nfrom_pod" | fzf --prompt="Copy to or from pod? ")

  case $action_choice in
  to_pod)
      echo -n "Enter the source path on your machine: "
      read src
      echo -n "Enter the destination path in the pod: "
      read dest
      ;;
  from_pod)
      echo -n "Enter the source path in the pod: "
      read src
      echo -n "Enter the destination path on your machine: "
      read dest
      ;;
  *)
      echo "Invalid action choice."
      return 1
      ;;
  esac

  command="kubectl cp"
  [[ -n "$container_name" ]] && command="$command -c $container_name"

  if [[ $action_choice == "to_pod" ]]; then
    command="$command $src $pod_name:$dest"
  else
    command="$command $pod_name:$src $dest"
  fi

  echo "Executing: $command"
  eval "$command"
}


port_forward_and_pgcli() {
    if [[ "$1" == "--help" ]]; then
        echo "Usage: port_forward_and_pgcli"
        echo "Port-forward a PostgreSQL pod and connect using pgcli."
        return 0
    fi

    # Select Kubernetes secret
    local secret_name
    secret_name=$(kubectl get secrets --no-headers=true | awk '{print $1}' | fzf --prompt="Select a secret: ")
    [[ -z "$secret_name" ]] && echo "No secret selected. 🚫" && return 1

    # Construct pod name based on the secret
    local pod_name="${secret_name}-0"

    # Port-forward the database
    kubectl port-forward pod/"$pod_name" 5433:5432 &
    
    # Wait for port-forward to be ready 🕒
    sleep 2

    # Set PostgreSQL password from the Kubernetes secret 🔑
    export PGPASSWORD=$(kubectl get secret "$secret_name" -o jsonpath="{.data.postgres-password}" | base64 -d)

    # Run pgcli 🐘
    pgcli -h 127.0.0.1 -p 5433 -U postgres
}


git_commit_last_cmd() {
  if [ -d .git ] || git rev-parse --git-dir > /dev/null 2>&1; then
    local last_cmd=$(fc -ln -1 | sed 's/^[[:space:]]*//')
    local interpreted_cmd=$(echo -e "$last_cmd")
    git add -A
    git commit -m "$interpreted_cmd"
    echo "Committed with message: $interpreted_cmd" 🚀
  else
    echo "Not a git repository. Aborting." 🛑
  fi
}

assume_role() {
    local role_arn="$1"
    
    local session_name="$2"

    local creds="$(aws sts assume-role --role-arn $role_arn --role-session-name $session_name --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text)"

    export AWS_ACCESS_KEY_ID="$(echo $creds | awk '{print $1}')"
    export AWS_SECRET_ACCESS_KEY="$(echo $creds | awk '{print $2}')"
    export AWS_SESSION_TOKEN="$(echo $creds | awk '{print $3}')"

    echo "🔐 AWS credentials set for session $session_name."
}

kill_by_port() {
  local port PID
  if [ "$1" = "--help" ]; then
    echo "📖 Usage: kill_by_port"
    echo "This function will list processes listening on ports and let you kill them."
    return 0
  fi

  port=$(lsof -i -n -P | grep LISTEN | awk '{print $9}' | sed 's/.*://g' | uniq | fzf --prompt="🔍 Select a port: ")

  if [ -z "$port" ]; then
    echo "🚫 No port selected."
    return 1
  fi

  PID=$(lsof -t -i:$port)

  if [ -z "$PID" ]; then
    echo "🚫 No process found on port $port"
    return 1
  fi

  echo "🔪 Killing process $PID on port $port"
  kill -9 $PID
}

get_k8s_node_info() {
    for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')
    do
        instance_id=$(kubectl get node "$node" -o jsonpath='{.spec.providerID}' | cut -d'/' -f5)
        instance_type=$(aws ec2 describe-instances --instance-ids "$instance_id" --query 'Reservations[].Instances[].InstanceType' --output text)
        node_status=$(kubectl get node "$node" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')

        # Fetching metrics
        metrics=$(kubectl top node "$node" | tail -n +2)
        cpu_usage=$(echo $metrics | awk '{print $2}')
        memory_usage=$(echo $metrics | awk '{print $4}')

        # Check if metrics are unknown
        if [[ "$cpu_usage" == "<unknown>" || "$memory_usage" == "<unknown>" ]]; then
            echo "Node: $node"
            echo "  Instance ID: $instance_id"
            echo "  Instance Type: $instance_type"
            echo "  Status: $node_status"
            echo "  Metrics: Unavailable (Node might be in a NotReady or similar state)"
        else
            cpu_percent=$(echo $metrics | awk '{print $3}')
            memory_percent=$(echo $metrics | awk '{print $5}')
            echo "Node: $node"
            echo "  Instance ID: $instance_id"
            echo "  Instance Type: $instance_type"
            echo "  CPU Usage: $cpu_usage ($cpu_percent)"
            echo "  Memory Usage: $memory_usage ($memory_percent)"
        fi
    done
}

aws_sso_login() {
    if [[ "$1" == "--help" ]]; then
        echo "Usage: aws_sso_login"
        echo "Logs into an AWS SSO profile using fzf to select the profile, and opens the login page in a specific Chrome profile."
        return 0
    fi

    local aws_profile chrome_profile output autofill_url

    aws_profile=$(awk '/^\[profile / {sub(/\[profile /, ""); sub(/\]/, ""); print}' ~/.aws/config | fzf --prompt="Select an AWS profile: ")

    [[ -z "$aws_profile" ]] && echo "No AWS profile selected." && return 1

    echo "Selected AWS profile: $aws_profile"

    echo "Setting AWS CLI Profile..."
    asp $aws_profile

    # Map AWS profiles to specific Chrome profiles
    case $aws_profile in
    clearstep_duplo_admin)
        chrome_profile="Profile 2"
        ;;
    clearstep_duplo_jit)
        chrome_profile="Profile 2"
        ;;
    clearstep_qadevint_admin | clearstep_qadevint_eng)
        chrome_profile="Profile 2"
        ;;
    ms-AdministratorAccess-504785860355)
        chrome_profile="Profile 1"
        ;;
    *)
        echo "Unknown AWS profile."
        return 1
        ;;
    esac

    local temp_file="$(mktemp)"

    echo "Running AWS SSO login command..."
    aws sso login --profile $aws_profile --no-browser > $temp_file 2>&1 &
    local aws_login_pid=$!  # Capture the PID of the background process

    start_time=$(date +%s)
    timeout=10
    autofill_url=""

    while [[ -z "$autofill_url" ]]; do
        # Check if the timeout has been reached
        current_time=$(date +%s)
        if (( current_time - start_time > timeout )); then
            echo "Timeout reached without finding the autofill URL."
            rm $temp_file
            return 1
        fi

        # Try to find the autofill URL
        autofill_url=$(grep -o 'https://device.sso.\(us\|eu\|ap\|sa\|ca\)-\([a-zA-Z0-9-]*\).amazonaws.com/?user_code=[A-Za-z0-9-]*' $temp_file)

        # Wait a bit before retrying
        sleep 0.5
    done

    cat $temp_file

    echo "Opening the URL in Chrome profile: $chrome_profile"
    open -na "Google Chrome" --args --profile-directory="$chrome_profile" "$autofill_url"

    # After opening the URL in Chrome, wait for the AWS SSO login process to complete
    wait $aws_login_pid
    local aws_login_exit_status=$?  # Capture the exit status

    rm $temp_file

    # Check the exit status
    if [[ $aws_login_exit_status -ne 0 ]]; then
        echo "AWS SSO login failed with exit code $aws_login_exit_status"
        return $aws_login_exit_status
    fi
}

# Usage:
# export_and_import_conversation_data "25d74cd0-2d91-4072-87fd-4045b00bdbb8"
function export_and_import_conversation_data() {
    local db_host="duploproddb.cz8h7rcmn3cv.us-west-2.rds.amazonaws.com"
    local db_user="clearstep"
    local db_name="triagedb"
    local conversation_uuid="$1"

    # Prompt for the database password
    read -s -p "Enter password for $db_user at $db_host: " db_pass
    echo

    # Export and import for 'conversations'
    PGPASSWORD="$db_pass" psql -h "$db_host" -U "$db_user" -d "$db_name" -c \
    "COPY (SELECT * FROM conversations WHERE uuid = '$conversation_uuid') TO STDOUT" | \
    PGPASSWORD="" psql -c "COPY conversations FROM STDIN"

    # Export and import for 'event_log'
    PGPASSWORD="$db_pass" psql -h "$db_host" -U "$db_user" -d "$db_name" -c \
    "COPY (SELECT * FROM event_log WHERE type IN ('CLICKED_PARTNER_CARE_OPTION', 'CLICKED_PARTNER_EXTERNAL_LINK', 'PHONE_NUMBER_CLICK') AND convo_uuid='$conversation_uuid') TO STDOUT" | \
    PGPASSWORD="" psql -c "COPY event_log FROM STDIN"

    # Export and import for 'metrics'
    PGPASSWORD="$db_pass" psql -h "$db_host" -U "$db_user" -d "$db_name" -c \
    "COPY (SELECT * FROM metrics WHERE conversation_uuid='$conversation_uuid') TO STDOUT" | \
    PGPASSWORD="" psql -c "COPY metrics FROM STDIN"

    # Export and import for 'nlp_results'
    PGPASSWORD="$db_pass" psql -h "$db_host" -U "$db_user" -d "$db_name" -c \
    "COPY (SELECT * FROM nlp_results WHERE conversation_uuid = '$conversation_uuid') TO STDOUT" | \
    PGPASSWORD="" psql -c "COPY nlp_results FROM STDIN"
}

pgcli_connect() {
    # Get a list of databases, then select one using fzf
    local db_selection=$(op item list --categories database | fzf --height=20% --layout=reverse --border --prompt='Select a database: ')

    # Extract the UUID from the selection
    local uuid=$(echo "$db_selection" | awk '{print $1}')

    # Retrieve and parse database details
    IFS=',' read -r server port database username password <<< $(op item get $uuid --fields server,port,database,username,password)

    # Connect to the database
    export PGPASSWORD=$password
    pgcli -h "$server" -p "$port" -U "$username" -d "$database" # Assuming username is the same as database name, adjust if necessary
    unset PGPASSWORD # Clear the variable afterwards
}