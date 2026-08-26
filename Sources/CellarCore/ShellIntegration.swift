import Foundation

public enum ShellIntegration {
    public static func zshInit(executableName: String = "cellar") -> String {
        #"""
        # Cellar shell integration. Records package identity and time only.
        if [[ -o interactive ]] && (( $+commands[\#(executableName)] )); then
          autoload -Uz add-zsh-hook
          zmodload -F zsh/datetime b:EPOCHSECONDS 2>/dev/null || true

          _cellar_preexec() {
            local -a _cellar_words
            _cellar_words=(${(z)1})
            local _cellar_expect=1 _cellar_word _cellar_path _cellar_rest _cellar_kind _cellar_token
            local _cellar_prefix=${HOMEBREW_PREFIX:-/opt/homebrew}
            local _cellar_events="${CELLAR_STATE_DIR:-$HOME/Library/Application Support/Cellar}/events.log"
            [[ -d ${_cellar_events:h} ]] || return 0
            _cellar_prefix=${_cellar_prefix:A}

            for _cellar_word in "${_cellar_words[@]}"; do
              case "$_cellar_word" in
                '|'|'||'|'&&'|';'|'&') _cellar_expect=1; continue ;;
              esac
              (( _cellar_expect )) || continue
              [[ "$_cellar_word" == *=* ]] && continue
              case "$_cellar_word" in
                builtin|command|env|exec|nice|nohup|sudo|time) continue ;;
                -*) continue ;;
              esac
              _cellar_expect=0
              _cellar_path=${commands[$_cellar_word]:-}
              [[ -n "$_cellar_path" ]] || continue
              _cellar_path=${_cellar_path:A}
              case "$_cellar_path" in
                "$_cellar_prefix"/Cellar/*)
                  _cellar_kind=formula
                  _cellar_rest=${_cellar_path#"$_cellar_prefix"/Cellar/}
                  ;;
                "$_cellar_prefix"/Caskroom/*)
                  _cellar_kind=cask
                  _cellar_rest=${_cellar_path#"$_cellar_prefix"/Caskroom/}
                  ;;
                *) continue ;;
              esac
              _cellar_token=${_cellar_rest%%/*}
              [[ -n "$_cellar_token" && "$_cellar_token" != *[$'\t\r\n/']* ]] || continue
              print -r -- $'1\t'"${EPOCHSECONDS:-0}"$'\t'"$_cellar_kind"$'\t'"$_cellar_token" >> "$_cellar_events"
            done
          }

          add-zsh-hook -D preexec _cellar_preexec 2>/dev/null || true
          add-zsh-hook preexec _cellar_preexec
          command \#(executableName) notice 2>/dev/null || true
        fi
        """#
    }
}
