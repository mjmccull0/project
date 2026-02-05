# Generated Zsh Code - 2026-02-05T05:36:43.294Z
_proj_menu_app_t() {
  echo -n "\n%F{yellow}[app > t]%f "
  echo "%F{cyan}u%f:npm test -- unit  %F{cyan}e%f:npm test -- e2e"
  read -k 1 char
  case "$char" in
    u)
      echo "\n🚀 Executing: npm test -- unit"
      eval "npm test -- unit" ;;
    e)
      echo "\n🚀 Executing: npm test -- e2e"
      eval "npm test -- e2e" ;;
    *) echo "\n%F{red}Aborted.%f" ;;
  esac
  zle reset-prompt
}
zle -N _proj_menu_app_t

_proj_menu_app() {
  echo -n "\n%F{yellow}[app]%f "
  echo "%F{cyan}b%f:project_build  %F{cyan}s%f:npm start  %F{cyan}t%f:..."
  read -k 1 char
  case "$char" in
    b)
      echo "\n🚀 Executing: project_build"
      if (( $+functions[project_build] )); then project_build; else eval "project_build"; fi ;;
    s)
      echo "\n🚀 Executing: npm start"
      eval "npm start" ;;
    t) _proj_menu_app_t ;;
    *) echo "\n%F{red}Aborted.%f" ;;
  esac
  zle reset-prompt
}
zle -N _proj_menu_app

# Key Bindings
bindkey -M project_map "^a" _proj_menu_app
