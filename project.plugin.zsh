# --- Plugin Initialization ---

# This MUST be at the top level of the file, not inside the function
# It captures the directory where this script lives
export PROJECT_NODE_ROOT="${0:A:h}"
export PROJECT_NODE_CACHE="$PROJECT_NODE_ROOT/cache"

# Ensure cache directory exists
[[ ! -d "$PROJECT_NODE_CACHE" ]] && mkdir -p "$PROJECT_NODE_CACHE"

# --- The Loader ---

load_project_config() {
    local json_config="./.project.json"
    
    # If no config, swap back to normal keys and exit
    if [[ ! -f "$json_config" ]]; then
        bindkey -l standard_map >/dev/null 2>&1 && bindkey -A standard_map main
        return
    fi

    # Generate a unique ID based on the directory path
    # We use 'cksum' as it's highly portable
    local project_id=$(pwd | cksum | cut -d' ' -f1)
    local compiled_zsh="$PROJECT_NODE_CACHE/proj_$project_id.zsh"

    # 1. Compile if JSON is newer or compiled file is missing
    if [[ "$json_config" -nt "$compiled_zsh" || ! -f "$compiled_zsh" ]]; then
        # Use the absolute path to Node and the compiler script
        node "$PROJECT_NODE_ROOT/project-compiler.js" > "$compiled_zsh" 2>/dev/null
        
        # Check if node command actually succeeded
        if [[ $? -ne 0 ]]; then
            echo "❌ project-node: Compilation failed. Check your JSON syntax."
            return 1
        fi
    fi

    # 2. Setup the Keymap
    bindkey -N project_map standard_map
    
    # 3. Source custom shell logic if present
    [[ -f "./.project.sh" ]] && source "./.project.sh"

    # 4. Source the compiled ZLE widgets
    source "$compiled_zsh"
    
    # 5. Atomic Swap
    bindkey -A project_map main
}

# Add the hook
autoload -Uz add-zsh-hook
add-zsh-hook chpwd load_project_config

# Initial run for the current directory
load_project_config
