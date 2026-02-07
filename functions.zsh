#!/bin/zsh

if ! command -v gum &> /dev/null; then
    echo "❌ Error: 'gum' is not installed."
    echo "Install it via: brew install gum (macOS) or go install github.com/charmbracelet/gum@latest"
    exit 1
fi

# Ensure the Zsh parameter module is available for widget management
zmodload zsh/parameter

# A generic wrapper to run any function safely in ZLE
_project_zle_wrapper() {
    # The name of the actual function is passed via a custom variable or state
    local target_func="$_CURRENT_PROJECT_WIDGET"

    if (( $+functions[$target_func] )); then
        # Run the actual project function
        "$target_func"
        # UI Housekeeping happens here, outside the .projectrc
        zle reset-prompt
    fi
}

zle -N _project_zle_wrapper

unload_project_context() {
    # 1. UNBIND KEYS
    # We parse 'bindkey -L' because it handles quoted key sequences perfectly
    local line
    bindkey -L | grep "project_" | while read -r line; do
        # ${(z)line} splits the line into shell-aware words
        # word [2] is the key sequence (e.g., "^B")
        local parts=(${(z)line})
        local key=$parts[2]

        eval "bindkey -r $key" 2>/dev/null
    done

    # 2. DELETE WIDGETS
    # This prevents "Widget Bloat" by removing them from ZLE entirely
    local w
    for w in ${(k)widgets}; do
        if [[ "$w" == project_* || "$w" == _zle_project_* ]]; then
            # Check if the widget actually exists before deleting
            if (( ${+widgets[$w]} )); then
                zle -D "$w" 2>/dev/null
                # Kill the function (the actual code in memory)
                unfunction "$w" 2>/dev/null
            fi
        fi
    done
}

load_project_config() {
    unload_project_context

    if [[ -f "./.projectrc" ]]; then
        unset PROJECT_KEYS
        typeset -gA PROJECT_KEYS

        source "./.projectrc"

        if (( ${#PROJECT_KEYS} > 0 )); then
            local k v
            for k v in ${(kv)PROJECT_KEYS}; do
                # Define a UI-aware version of the project function on the fly
                eval "
                    _zle_$v() {
                        $v              # Call the original function from .projectrc
                        zle reset-prompt # Perform the reset
                    }
                "
                zle -N "_zle_$v" "_zle_$v"
                bindkey "$k" "_zle_$v"
            done
        fi
    fi
}

# Register the hook
# We use += to avoid overwriting other hooks (like oh-my-zsh themes)
autoload -Uz add-zsh-hook
add-zsh-hook chpwd load_project_config

# Run it once on startup in case you open the terminal already in a project dir
load_project_config

# The main entry point
project() {
    [[ -f "./.projectrc" ]] && source "./.projectrc"

    local cmd=$1
    # Only shift if $cmd is not empty
    [[ -n "$cmd" ]] && shift


    if whence "project_$cmd" >/dev/null; then
        "project_$cmd" "$@"
        return $?
    fi

    case "$cmd" in
        branch) branch_router "$@" ;;
        init)   project_init ;;
        *)
            local -a choices
            # Add core commands
            choices=(branch)

            # Add 'init' ONLY if .projectrc does not exist
            [[ ! -f "./.projectrc" ]] && choices+=(init)
            # Add only the KEYS (command names) from your Associative Array
            if (( ${#PROJECT_CUSTOM_COMMANDS} > 0 )); then
                choices+=("${(@k)PROJECT_CUSTOM_COMMANDS}")
            fi

            # Let the user choose
            local choice=$(gum choose --header "Select a project task" "${choices[@]}")

            # Handle exit or selection
            [[ -z "$choice" || $? -eq 130 ]] && return
            project "$choice"
            ;;
    esac
}


get_conventional_message() {
    local -a types
    if (( ${#PROJECT_COMMIT_TYPES[@]} > 0 )); then
        types=("${PROJECT_COMMIT_TYPES[@]}")
    else
        types=("fix" "feat" "docs" "style" "refactor" "chore")
    fi

    # 1. Type Selection
    local type=$(gum choose --header "Commit Type" "${types[@]}")

    [[ $? -eq 130 ]] && return 130
    
    # 2. The Subject Line
    local subject=$(gum input --placeholder "Commit message (Short and descriptive)")
    [[ $? -eq 130 ]] && return 130
    [[ -z "$subject" ]] && return 130

    # 3. The Optional Description
    # We use write here so they have room if they need it, 
    # but the header tells them they can skip it instantly.
    local body=$(gum write --header "Extended description? (Optional. Ctrl+D to save/skip)" --width 80)
    [[ $? -eq 130 ]] && return 130
    
    # 4. Construct the Final String
    local full_msg=""
    if [[ -n "$body" ]]; then
        # Ensures the mandatory blank line between subject and body
        full_msg=$(echo -e "${type}: ${subject}\n\n${body}")
    else
        full_msg="${type}: ${subject}"
    fi

    # 5. Final Confirmation Loop
    {
      echo 'Review' | gum style --underline --bold >&2
      echo "${full_msg}" | gum style --bold >&2
    } >&2
    local action=$(gum choose "Confirm" "Edit" "Abort")
    local exit_status=$?

    # Handle Ctrl+C or "Abort" selection
    if [[ $exit_status -eq 130 || "$action" == "Abort" ]]; then
        return 130
    fi
    
    case "$action" in
        "Confirm") echo -e "$full_msg"; return 0 ;;
        "Edit")    get_conventional_message; return $? ;; # Recursive restart
        *)         return 130 ;;
    esac
}

project_branch_create() {
    local name=$(gum input --placeholder "New branch name")
    echo "Creating branch: $name"
    git checkout -b "$name"
}

project_branch_menu(){
    # Discovery Mode: No action provided, so ask!
    local choice=$(gum choose \
      "amend" \
      "backup" \
      "commit" \
      "create" \
      "diff" \
      "push" \
      "rebase" \
      "reset" \
      "squash" \
      "status" \
      "switch" \
      "undo" \
    )
    local exit_status=$?

    [[ $exit_status -eq 130 ]] && return 130

    [[ -n "$choice" ]] && branch_router "$choice"
}

# The Branch Router
branch_router() {
    local action=$1

    (( $# > 0 )) && shift

    case "$action" in
        amend)  amend_commit "$@" ;;
        backup) project_snapshot "$@" ;;
        commit) project_commit ;;
        create) project_branch_create ;;
        diff) project_diff "$@" ;;
        push)   project_push ;;
        rebase) project_rebase "$@" ;;
        reset)  project_reset ;;
        squash) project_squash ;;
        status) git status ;;
        status) git status ;;
        switch) project_branch_switch ;;
        undo)   project_undo_wizard "$@" ;;
        *) project_branch_menu ;;
    esac
}

commit_wizard() {
    if git diff --cached --quiet; then
        echo "❌ Error: Nothing staged to commit." >&2
        return 1
    fi

    local full_msg=$(get_conventional_message)
    [[ $? -eq 130 ]] && return 130
    
    git commit -m "$full_msg"
}


# Inside your project script
stage_files() {
    # Get unstaged/untracked files
    local files=$(git status --porcelain | grep -E '^( M| M|\?\?)' | sed 's/^...//')

    if [ -n "$files" ]; then
        echo "Unstaged changes detected:"
        local selected=$(echo "$files" | gum filter --no-limit --placeholder "Select files to stage (Tab to multi-select)")

        if [ -n "$selected" ]; then
            echo "$selected" | xargs git add
            echo "Files staged!"
        fi
    fi
}

amend_commit() {
    smart_stage
    [[ $? -ne 0 ]] && return $?

    # Show them what they are about to change
    echo "Last commit:" >&2
    git --no-pager log -1 --format='%C(yellow)%h%C(reset) %s'
    git status

    if gum confirm "Amend the last commit with current staged changes?"; then
        if gum confirm "Keep existing commit message?"; then
            git commit --amend --no-edit
        else
            # Use the helper to get a fresh conventional message
            local full_msg=$(get_conventional_message)
            if [[ $? -eq 130 || -z "$full_msg" ]]; then
                return 130
            fi
            
            git commit --amend -m "$full_msg"
            echo "✅ Amended successfully." >&2
        fi
    fi
}

project_reset() {
    # Get the last 10 commits for selection
    local target=$(git log -n 10 --oneline | gum choose | awk '{print $1}')
    
    if [ -n "$target" ]; then
        echo "WARNING: This will revert all files to match commit $target."
        if gum confirm "Are you absolutely sure? Unsaved changes will be lost."; then
            git reset --hard "$target"
            echo "HEAD is now at $target"
        fi
    fi
}

# Silently restores stash only if we created one
restore_stash_if_needed() {
    local stash_signal=$1
    if [[ "$stash_signal" == "stashed" ]]; then
        git stash pop -q > /dev/null 2>&1
    fi
}

project_squash() {
    local stash_result=$(ensure_clean_working_tree)
    [[ $? -eq 130 ]] && return 130

    local squashable_commits=$(git log -n 20 --oneline --min-parents=1)
    local chosen_hash=$(echo "$squashable_commits" | gum choose --header "Select the oldest commit to include in the squash" | awk '{print $1}')
    
    # If cancelled, restore and exit
    [[ -z "$chosen_hash" ]] && { restore_stash_if_needed "$stash_result"; return; }

    local target="${chosen_hash}~1"
    
    if gum confirm "Collapse selected commits?"; then
        git reset --soft "$target" > /dev/null
        commit_wizard
    fi

    restore_stash_if_needed "$stash_result"
}

project_undo_wizard() {
    local stash_result=$(ensure_clean_working_tree)
    [[ $? -eq 130 ]] && return 130

    local squashable_commits=$(git log -n 15 --oneline --min-parents=1)

    if [[ -z "$squashable_commits" ]]; then
        echo "No commits available to undo." >&2
        restore_stash_if_needed "$stash_result"
        return 1
    fi

    local target_selection=$(echo "$squashable_commits" | gum choose --header "Select the OLDEST commit to undo")
    [[ -z "$target_selection" ]] && { restore_stash_if_needed "$stash_result"; return; }
    
    local selected_hash=$(echo "$target_selection" | awk '{print $1}')
    local reset_target="${selected_hash}~1"

    local mode=$(gum choose --header "How should we handle the undone changes?" \
        "Soft (Keep and Stage)" "Mixed (Keep but Unstage)" "Hard (Delete Everything)")
    
    [[ -z "$mode" ]] && { restore_stash_if_needed "$stash_result"; return; }

    case "$mode" in
        "Soft"*)  git reset --soft "$reset_target" > /dev/null ;;
        "Mixed"*) git reset --mixed "$reset_target" > /dev/null ;;
        "Hard"*)  
            if gum confirm "🔥 PERMANENTLY DELETE these commits?"; then
                git reset --hard "$reset_target" > /dev/null
            fi
            ;;
    esac

    restore_stash_if_needed "$stash_result"
}

smart_stage() {
    local raw_status=$(git status --porcelain)

    # If the working tree is literally empty, tell the user and exit
    if [[ -z "$raw_status" ]]; then
        echo "Nothing to commit, working tree clean."
        return 1
    fi

    local file_list=$(echo "$raw_status" | cut -c4-)
    local staged_files=$(echo "$raw_status" | grep -E '^[MADRC]' | cut -c4-)

    selections=$(echo "$file_list" | gum choose \
        --header "Changes to be committed:" \
        --no-limit \
        --selected-prefix="[x] " \
        --unselected-prefix="[ ] " \
        --cursor-prefix="[ ] " \
        --selected="$staged_files")

    local exit_code=$?

    # If $? (the exit status of gum) is not 0, the user hit Ctrl+C or Esc
    if [[ $exit_code -eq 130 ]]; then
        return 130 
    fi

    # If they hit Enter but didn't select anything
    if [[ -z "$selections" ]]; then
        echo "No files selected."
        return 1
    fi

    git reset HEAD -- . > /dev/null
    echo "$selections" | while read -r file; do
        [[ -n "$file" ]] && git add "$file"
    done

    return 0
}

project_commit() {
    smart_stage
    local result=$?

    # If smart_stage was interrupted or failed, stop here.
    if [[ $result -ne 0 ]]; then
        return $result
    fi
    [[ $? -eq 130 ]] && return 130
    
    commit_wizard
}

ensure_clean_working_tree() {
    if [[ -n "$(git status --porcelain)" ]]; then
        # Replace default "Choose:" with a custom header
        local action=$(gum choose --header "Uncommitted changes detected. How to proceed?" \
            "Stash everything and continue" "Abort")
        
        if [[ "$action" == "Stash everything and continue" ]]; then
            # -q (quiet) suppresses the "Saved working directory..." logs
            git stash push -u -q -m "Auto-stash: $(date +%H:%M:%S)"
            echo "stashed" 
            return 0
        else
            return 130
        fi
    fi
    echo "clean"
    return 0
}

project_push() {
    local branch=$(git rev-parse --abbrev-ref HEAD)
    
    # 1. First, check the current local state
    local git_status=$(git rev-list --left-right --count $branch...origin/$branch 2>/dev/null)
    local behind=$(echo $git_status | awk '{print $2}')

    # 2. If we aren't sure, or if the user wants to be sure, offer a fetch
    if [[ "$behind" -eq 0 ]]; then
        echo "Pushing normally..." >&2
        if ! git push origin "$branch"; then
            echo "❌ Push failed. You might be out of sync." >&2
            if gum confirm "Fetch latest remote status and retry?"; then
                git fetch origin > /dev/null
                project_push # Recursive call to re-evaluate with new data
                return
            fi
        fi
    else
        # 3. Handle the Divergence (Squash/Undo aftermath)
        echo "⚠️  Local history has diverged from origin/$branch." >&2
        
        local action=$(gum choose --header "Divergence detected. How to proceed?" \
            "Force-with-lease (Safe Force)" \
            "Rebase then Push (Cleanest)" \
            "Nuclear Force (Overwrite)" \
            "Abort")

        case "$action" in
            "Force-with-lease"*)
                git push origin "$branch" --force-with-lease
                ;;
            "Rebase"*)
                git pull --rebase origin "$branch" && git push origin "$branch"
                ;;
            "Nuclear Force"*)
                if gum confirm "Overwrite remote history? This cannot be undone."; then
                    git push origin "$branch" --force
                fi
                ;;
            *) return 130 ;;
        esac
    fi
}

project_reset() {
    echo "⚠️  WARNING: This will permanently delete all uncommitted changes and new files." >&2
    
    if gum confirm "Are you sure you want to wipe the workspace?"; then
        # Reset tracked files to the last commit
        git reset --hard HEAD > /dev/null 2>&1
        
        # Delete untracked files (-f = force, -d = directories)
        git clean -fd > /dev/null 2>&1
        
        echo "✨ Rest branch state." >&2
    else
        echo "Wipe aborted." >&2
    fi
}

project_rebase() {
    # 1. Ensure a clean working tree (or stash if the user agrees)
    local stash_result=$(ensure_clean_working_tree)
    [[ $? -eq 130 ]] && return 130

    # 2. Select the target to rebase onto
    # We'll offer local branches, but also allow the user to see remote branches
    echo "Select a target branch to rebase onto:" >&2
    local target=$(git branch -a --format="%(refname:short)" | sed 's/origin\///' | sort -u | gum filter --placeholder "Target branch (e.g., main, develop)...")

    # If the user escaped/cancelled
    if [[ -z "$target" ]]; then
        restore_stash_if_needed "$stash_result"
        return 130
    fi

    # 3. Choose the type of rebase
    local mode=$(gum choose "Standard Rebase" "Interactive (-i)")
    
    echo "Starting rebase onto $target..." >&2

    # 4. Execute
    if [[ "$mode" == "Interactive"* ]]; then
        # Use vared or just execute git directly since -i needs a real TTY/editor
        git rebase -i "$target"
    else
        git rebase "$target"
    fi

    local exit_status=$?

    # 5. Handle Results
    if [[ $exit_status -eq 0 ]]; then
        echo "✅ Rebase completed successfully." >&2
        restore_stash_if_needed "$stash_result"
    else
        echo "⚠️  Rebase paused or failed due to conflicts." >&2
        echo "1. Resolve conflicts manually." >&2
        echo "2. Run 'git rebase --continue'." >&2
        echo "3. Your auto-stashed changes (if any) are still in the stash list." >&2
        return $exit_status
    fi
}

project_snapshot() {
    # 1. Select the branch you want to copy
    echo "Select branch to snapshot:" >&2
    local source_branch=$(git branch --format="%(refname:short)" | gum filter --placeholder "Search branch to backup...")

    # Handle Ctrl+C / Escape
    [[ -z "$source_branch" ]] && return 130

    # 2. Name the new backup branch
    # Pre-filling with 'backup/' is a common convention to keep the sidebar clean
    local backup_name=$(gum input --value "backup/$source_branch-$(date +%Y%m%d-%H%M)" --placeholder "Name of the backup branch")

    # Handle Ctrl+C / Escape or empty input
    [[ -z "$backup_name" ]] && return 130

    # 3. Create the branch (without switching to it)
    # This creates $backup_name pointing at the current state of $source_branch
    if git branch "$backup_name" "$source_branch" 2>/dev/null; then
        echo "✅ Snapshot created: $backup_name" >&2
    else
        echo "❌ Error: Could not create backup. (Branch name might already exist)" >&2
        return 1
    fi
}

project_branch_switch() {
  # Logic for switching
  local target=$(git branch -a --format="%(refname:short)" | sed 's|^origin/||' | sort -u | gum filter)
  git checkout "$target"
}

project_diff() {
  project_branch_diff
}

project_branch_diff() {
    while true; do
        # 1. Get the list of modified files
        local files=$(git status --porcelain | sed 's/^...//')

        if [[ -z "$files" ]]; then
            echo "✨ No modified files to inspect."
            return 0
        fi

        # 2. Pick a file to inspect
        local selected=$(echo "$files" | gum filter --placeholder "Select a file to see its diff (Esc to exit)...")

        # Exit the loop if they hit Escape or Ctrl+C
        [[ -z "$selected" ]] && break

        # 3. Show the diff using a pager
        # We use --color=always so the colors stay when piped to the pager
        git diff --color=always "$selected" | gum pager

        # The loop repeats, bringing you back to the file list!
    done
}

project_init() {
    # 1. Check if the target already exists to prevent accidental overwrites
    if [[ -f "./.projectrc" ]]; then
        echo "⚠️  .projectrc already exists."
        return 1
    fi

    # 2. Check if the example template actually exists
    if [[ -f "./.projectrc.example" ]]; then
        cp ./.projectrc.example ./.projectrc
        echo "✅ Created .projectrc from .projectrc.example."
    else
        echo "❌ Error: .projectrc.example not found in this directory."
        return 1
    fi

    # Trigger your loader immediately so hotkeys work now
    load_project_config
}
