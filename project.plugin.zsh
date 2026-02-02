# Is this needed?
fpath+=( "${0:h}/completions" )

# Get the directory this plugin is stored in
PLUGIN_DIR="${0:h}"

fpath=("$PLUGIN_DIR/completions" $fpath)

# Automatically source the functions file
[[ -f "$PLUGIN_DIR/functions.zsh" ]] && source "$PLUGIN_DIR/functions.zsh"

# Define an alias if you want a shorter command
alias p='project'
