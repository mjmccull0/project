# --- Helper to handle opening files ---
# This can be reused by both project_find and project_grep
_project_open_file() {
    local file=$1
    local line=$2

    # 1. Check if $EDITOR is set and not empty
    if [[ -n "$EDITOR" ]]; then
        # Handle line jumping for common editors
        case "$EDITOR" in
            *vim*|*nano*)
                # Vim and Nano use +LINE
                $EDITOR "+$line" "$file"
                ;;
            *code*)
                # VS Code uses -g FILE:LINE
                $EDITOR -g "$file:$line"
                ;;
            *)
                # Fallback for editors that might not support line flags via CLI
                $EDITOR "$file"
                ;;
        esac
    else
        # 2. If $EDITOR isn't set, try 'open' (macOS) or 'xdg-open' (Linux)
        if command -v open &> /dev/null; then
            open "$file"
        elif command -v xdg-open &> /dev/null; then
            xdg-open "$file"
        else
            # 3. Final fallback: just print the path
            echo "No \$EDITOR set. Selected: $file (Line: $line)"
        fi
    fi
}

project_grep() {
    # Check for tools
    local has_bat=$(command -v bat)
    local has_rg=$(command -v rg)
    
    # 1. Fallback for content searching
    local find_cmd="rg --column --line-number --no-heading --color=always --smart-case --glob '!.git/*' ."
    if [[ -z "$has_rg" ]]; then
        find_cmd="grep -rnE . --exclude-dir={.git,node_modules}"
    fi

    # 2. Run FZF with fixed bat parsing
    # The --delimiter and --with-nth are key here to make the list look clean
    local selected=$(eval "$find_cmd" | fzf \
        --ansi \
        --height=25 \
        --header "Search Content | ENTER: Open | CTRL-D/U: Scroll Preview" \
        --delimiter : \
        --preview-window 'up,60%,border-bottom' \
        --preview "[[ -n {1} ]] && bat --color=always --style=numbers --highlight-line {2} {1} 2>/dev/null || cat {1} | head -100" \
        --bind "ctrl-d:preview-page-down,ctrl-u:preview-page-up")

    # 3. Open in Editor
    if [[ -n "$selected" ]]; then
        local file=$(echo "$selected" | cut -d: -f1)
        local line=$(echo "$selected" | cut -d: -f2)
        _project_open_file "$file" "$line"
    fi
}

# --- File Searcher ---
project_find() {
    local has_fd=$(command -v fd)
    local find_cmd="fd --type f --hidden --exclude .git --exclude node_modules"
    [[ -z "$has_fd" ]] && find_cmd="find . -type f -not -path '*/.*' -not -path './node_modules/*'"

    local selected=$(eval "$find_cmd" | fzf \
        --height=25 \
        --header "Find File | ENTER: Open | TAB: Multi-select" \
        --preview "bat --color=always --style=numbers --line-range=:100 {} 2>/dev/null || cat {} | head -100")

    [[ -n "$selected" ]] && echo "$selected" | xargs -r _project_open_file 
}

project_search() {
  project_grep
}

# --- Dynamic Diff Tool ---
diff_test() {
    local target_branch="dev"
    local current_base="HEAD"
    local last_file=""

    while true; do
        # Get list of modified files
        local files=$(git status --porcelain | sed 's/^...//')
        
        if [[ -z "$files" ]]; then 
            echo "No changes found."
            return
        fi

        # --query="$last_file" maintains focus on the previously selected item
        local out=$(echo "$files" | fzf \
            --query="$last_file" \
            --expect=ctrl-g,ctrl-t,ctrl-r \
            --preview "git diff --color=always $current_base -- {}" \
            --preview-window 'right:65%:wrap' \
            --header "Base: $current_base | [Ctrl-T] Toggle vs $target_branch | [Ctrl-G] Set Target | [Ctrl-R] Reset")

        # fzf returns the key on line 1 and the selected file on line 2
        local key=$(echo "$out" | head -1)
        local selection=$(echo "$out" | sed -n '2p')

        # Remember the file so we can re-highlight it in the next loop iteration
        if [[ -n "$selection" ]]; then
            last_file="$selection"
        fi

        case "$key" in
            ctrl-t) 
                # Toggle logic
                if [[ "$current_base" == "HEAD" ]]; then
                    current_base="$target_branch"
                else
                    current_base="HEAD"
                fi
                ;;
            ctrl-g) 
                # Set a new target branch via fzf
                local choice=$(git branch -a --format="%(refname:short)" | sed 's/origin\///' | sort -u | fzf --height=15 --border --header "Select New Target Branch")
                if [[ -n "$choice" ]]; then 
                    target_branch="$choice"
                    current_base="$choice"
                fi
                ;;
            ctrl-r) 
                # Reset view back to current local changes
                current_base="HEAD"
                ;;
            "") # Enter or Esc was pressed
                break
                ;;
            *)
                break
                ;;
        esac
    done
}


# Toggle this to 'true' to see the commands being run
VERBOSE_GIT=true

# Helper function to log and run
run_git() {
    local cmd="$*"
    if [[ "$VERBOSE_GIT" == "true" ]]; then
        # Prints in bold cyan to stand out from standard output
        printf "\n\e[1;36m>> Running: %s\e[0m\n" "$cmd"
    fi
    eval "$cmd"
}

project_sync_reset() {
    # This remains 'silent' as it's just fetching metadata
    git fetch origin > /dev/null 2>&1

    local target=$(git log -n 20 --oneline --decorate --branches --remotes | 
                  gum choose --header "Select commit (Look for origin/branch-name)" | 
                  awk '{print $1}')
    
    if [[ -n "$target" ]]; then
        if gum confirm "Hard reset to $target?"; then
            run_git "git reset --hard $target"
        fi
    fi
}

# project_port() {
#     # Example logic for your cherry-pick range
#     local start_commit="a5ffbed7"
#     local end_commit="a2054a73"
# 
#     echo "Preparing to port commits from $start_commit to $end_commit..."
#     
#     if gum confirm "Execute cherry-pick range?"; then
#         # We use the ^ to include the start commit as discussed
#         run_git "git cherry-pick ${start_commit}^..${end_commit}"
#     fi
# }
project_conflicts() {
    local files=$(git diff --name-only --diff-filter=U)
    if [[ -z "$files" ]]; then
        echo "No conflicts found!"
    else
        echo "Files needing resolution:"
        echo "$files"
        if gum confirm "Open these files in $EDITOR?"; then
            echo "$files" | xargs "$EDITOR"
        fi
    fi
}

project_cherry_pick() {
    # 1. Select the source branch
    local source_branch=$(git branch -a --format="%(refname:short)" | 
                          sed 's|^origin/||' | sort -u | 
                          fzf --height=15 --header "Select Source Branch to pick from")
    
    [[ -z "$source_branch" ]] && return

    # 2. Select Commits (FZF shows Newest at top)
    # Use TAB to select multiple, ENTER to confirm
    local raw_selections=($(git log "$source_branch" --oneline -n 50 | 
                            fzf --multi --header "TAB to select, ENTER to finish" | 
                        awk '{print $1}'))

    [[ ${#raw_selections[@]} -eq 0 ]] && return

    # 3. CRITICAL: Re-sort selections chronologically (Oldest to Newest)
    # This uses Git's own history tree to ensure dependencies are met.
    local sorted_selections=($(git rev-list --no-walk --topo-order --reverse "${raw_selections[@]}"))

    # 4. Execution Logic
    if [[ ${#sorted_selections[@]} -eq 1 ]]; then
        # Single Commit
        run_git "git cherry-pick ${sorted_selections[1]}"
    else
        # Identify the 'bookends' for a possible range
        local oldest=${sorted_selections[1]}
        local newest=${sorted_selections[-1]}
        
        # Check if the selection is a continuous block in the git history
        local range_count=$(git rev-list --count "${oldest}^..${newest}")
        
        if [[ "$range_count" -eq ${#sorted_selections[@]} ]]; then
            # Sequential Range: Use the clean range syntax (wrapped in quotes for Zsh)
            run_git "git cherry-pick '${oldest}^..${newest}'"
        else
            # Non-sequential: Loop through the sorted list
            printf "\e[1;33mApplying %s commits in chronological order...\e[0m\n" "${#sorted_selections[@]}"
            for commit in "${sorted_selections[@]}"; do
                run_git "git cherry-pick $commit" || {
                    printf "\n\e[1;31mSTOPPED: Conflict detected at %s\e[0m\n" "$commit"
                    printf "Resolve conflicts, 'git add', and run 'git cherry-pick --continue'\n"
                    return 1
                }
            done
        fi
    fi
}

project_branch_delete() {
    # 1. Force silence by disabling execution tracing inside this function
    # 'unsetopt xtrace' turns off the command dumping you see in your screenshot
    [[ -n "$ZSH_VERSION" ]] && unsetopt xtrace 2>/dev/null

    local scope="mine"
    local type="local"
    local user_name=$(git config user.name)
    local protected_branches="(main|master|dev|development|production|staging)"

    while true; do
        clear 

        local view_info="\e[1;32m[SCOPE: ${scope:u} | TYPE: ${type:u}]\e[0m"
        local header="$view_info  'm': Mine | 'a': All | 'l': Local | 'r': Remote | 'b': Both | 'd': Delete | ESC: Exit"
        
        # 2. Build branch list into a local variable quietly
        local branches_list=""
        if [[ "$scope" == "mine" ]]; then
            branches_list=$(git for-each-ref --format='%(authorname)|%(refname:short)' refs/heads refs/remotes | grep "^$user_name|" | cut -d'|' -f2)
        else
            branches_list=$(git branch -a --format='%(refname:short)' | sed 's|^origin/||' | sort -u)
        fi

        # 3. Apply Local/Remote filtering
        case $type in
            local)  branches_list=$(echo "$branches_list" | grep -v '^origin/') ;;
            remote) branches_list=$(echo "$branches_list" | grep '^origin/') ;;
        esac

        # 4. Filter out protected branches and current branch
        local filtered_branches=$(echo "$branches_list" | 
                                 grep -vE "HEAD|$protected_branches" | 
                                 grep -v "^$(git branch --show-current)$" | 
                                 sort -u)

        # 5. Run FZF (Ensuring no output leaks during selection)
        local out=$(echo "$filtered_branches" | 
                   fzf --height=20 --header-first --ansi --header "$(echo -e $header)" \
                       --expect="m,a,l,r,b,d" --header-lines=0)

        local key=$(head -1 <<< "$out")
        local branch=$(sed -n '2p' <<< "$out")

        [[ -z "$key" ]] && break

        case $key in
            m) scope="mine"; continue ;;
            a) scope="all"; continue ;;
            l) type="local"; continue ;;
            r) type="remote"; continue ;;
            b) type="both"; continue ;;
        esac

        # 6. Deletion Logic
        if [[ -n "$branch" && "$key" == "d" ]]; then
            local clean_name=$branch
            local is_remote=false
            [[ "$branch" == origin/* ]] && is_remote=true && clean_name="${branch#origin/}"

            echo -n "\e[1;33mDelete ${is_remote:+REMOTE }branch '$clean_name'? [y/N]: \e[0m"
            read -k 1 confirm; echo ""

            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                if [[ "$is_remote" == true ]]; then
                    run_git "git push origin --delete $clean_name"
                else
                    if ! git branch -d "$clean_name" 2>/dev/null; then
                        echo -n "\e[1;31mBranch not merged. Force delete? [y/N]: \e[0m"
                        read -k 1 force_confirm; echo ""
                        [[ "$force_confirm" =~ ^[Yy]$ ]] && run_git "git branch -D $clean_name"
                    else
                        printf "\e[1;32mDeleted branch %s\e[0m\n" "$clean_name"
                    fi
                fi
                sleep 1
            fi
        fi
    done
}
# Newest delete code with a different name.
project_branch_clean() {
    [[ -n "$ZSH_VERSION" ]] && unsetopt xtrace 2>/dev/null

    printf "\e[1;34mSyncing with remote and pruning stale references...\e[0m\n"
    git fetch --prune

    local scope="mine"
    local type="local"
    local user_name=$(git config user.name)
    local protected_branches="(main|master|dev|development|production|staging)"
    local main_branch="main" 

    while true; do
        clear 

        local line1="\e[1;32m[SCOPE: ${scope:u} | TYPE: ${type:u}]\e[0m"
        local line2="'m': Mine | 'a': All | 'l': Local | 'r': Remote | 'b': Both"
        local line3="\e[1;33mAction -> 'd': Delete\e[0m | ESC: Exit"
        local full_header=$(printf "$line1\n$line2\n$line3")
        
        # 1. Generate the list
        local raw_list=""
        if [[ "$scope" == "mine" ]]; then
            raw_list=$(git for-each-ref --format='%(authorname)|%(refname:short)' refs/heads refs/remotes | grep "^$user_name|" | cut -d'|' -f2)
        else
            raw_list=$(git branch -a --format='%(refname:short)' | sed 's|^  *||')
        fi

        # 2. Filter by Type
        local filtered_list=""
        case $type in
            local)  filtered_list=$(echo "$raw_list" | grep -v '^origin/') ;;
            remote) filtered_list=$(echo "$raw_list" | grep '^origin/') ;;
            both)   filtered_list="$raw_list" ;;
        esac

        local final_display=$(echo "$filtered_list" | grep -vE "HEAD|$protected_branches" | grep -v "^$(git branch --show-current)$" | sort -u)

        local out=$(echo "$final_display" | fzf --height=20 --header-first --ansi --header "$full_header" --expect="m,a,l,r,b,d" --header-lines=0)
        local key=$(head -1 <<< "$out")
        local branch=$(sed -n '2p' <<< "$out")

        [[ -z "$key" ]] && break

        case $key in
            m) scope="mine"; continue ;;
            a) scope="all"; continue ;;
            l) type="local"; continue ;;
            r) type="remote"; continue ;;
            b) type="both"; continue ;;
        esac

        if [[ -n "$branch" && "$key" == "d" ]]; then
            # --- IDENTIFY TARGET ---
            local clean_name=$branch
            local is_remote=false
            if [[ "$branch" == origin/* ]]; then
                is_remote=true
                clean_name="${branch#origin/}"
            fi

            if [[ "$is_remote" == true ]]; then
                # --- REMOTE DELETE PATH ---
                # Double check: Does it REALLY exist on the server?
                if ! git ls-remote --exit-code --heads origin "$clean_name" >/dev/null 2>&1; then
                    printf "\e[1;31mBranch '%s' no longer exists on the server. Cleaning local ghost ref...\e[0m\n" "$clean_name"
                    git branch -dr "origin/$clean_name" 2>/dev/null
                    sleep 1; continue
                fi

                # Safety: Ownership & Merge check (from previous step)
                local author=$(git log -1 --format='%an' "origin/$clean_name" 2>/dev/null)
                if [[ "$author" != "$user_name" ]]; then
                    printf "\e[1;31mPROTECTION: This belongs to %s, not you.\e[0m\n" "$author"
                    sleep 2; continue
                fi

                echo -n "\e[1;31mConfirm: Delete REMOTE branch '$clean_name' from server? [y/N]: \e[0m"
                read -k 1 confirm; echo ""
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    run_git "git push origin --delete $clean_name"
                fi
            else
                # --- LOCAL DELETE PATH ---
                echo -n "\e[1;33mDelete LOCAL branch '$clean_name'? [y/N]: \e[0m"
                read -k 1 confirm; echo ""
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    if ! git branch -d "$clean_name" 2>/dev/null; then
                        echo -n "\e[1;31mNot merged. Force local delete? [y/N]: \e[0m"
                        read -k 1 force_confirm; echo ""
                        [[ "$force_confirm" =~ ^[Yy]$ ]] && run_git "git branch -D $clean_name"
                    else
                        printf "\e[1;32mDeleted local branch %s\e[0m\n" "$clean_name"
                    fi
                fi
            fi
            sleep 1
        fi
    done
}

project_branch_new() {
    # 1. Select the Source Branch
    # We show both local and remote so you can branch off anything
    local source_branch=$(git branch -a --format='%(refname:short)' | 
                         sed 's|^origin/||' | 
                         sort -u | 
                         fzf --height=15 --header "Select SOURCE branch (ESC to cancel)")

    [[ -z "$source_branch" ]] && return

    # 2. Suggest a name with a timestamp
    local timestamp=$(date +%Y%m%d-%H%M)
    local default_name="${source_branch}-backup-${timestamp}"

    echo -n "\e[1;32mNew branch name\e[0m [\e[1;30m$default_name\e[0m]: "
    read new_branch
    
    # If user just hits Enter, use the default timestamped name
    [[ -z "$new_branch" ]] && new_branch=$default_name

    # 3. Create and switch
    # Use run_git to log the action if VERBOSE_GIT is true
    run_git "git checkout -b $new_branch $source_branch"
}
