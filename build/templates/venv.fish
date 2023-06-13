#!/usr/bin/env fish

# template variables starts
set build_name "{{build_name}}"
set workspace_path "{{workspace_path}}"
# template variables ends

if test (echo $FISH_VERSION | head -c 1) -lt 3
    echo "Fish version 3.0.0 or higher is required."
end

set -xg BUILD_NAME "$build_name"

# Modified from virtualenv: https://github.com/pypa/virtualenv/blob/main/src/virtualenv/activation/fish/activate.fish

set -xg KONG_VENV "$workspace_path/bazel-bin/build/$build_name"

# set PATH
if test -n "$_OLD_KONG_VENV_PATH"
    # restore old PATH first, if this script is called multiple times
    set -gx PATH $_OLD_KONG_VENV_PATH
else
    set _OLD_KONG_VENV_PATH $PATH
end

function deactivate -d 'Exit Kong\'s venv and return to the normal environment.'

    # reset old environment variables
    if test -n "$_OLD_KONG_VENV_PATH"
        set -gx PATH $_OLD_KONG_VENV_PATH
        set -e _OLD_KONG_VENV_PATH
    end

    if test -n "$_OLD_FISH_PROMPT_OVERRIDE"
       and functions -q _old_fish_prompt
        # Set an empty local `$fish_function_path` to allow the removal of `fish_prompt` using `functions -e`.
        set -l fish_function_path

        # Erase virtualenv's `fish_prompt` and restore the original.
        functions -e fish_prompt
        functions -c _old_fish_prompt fish_prompt
        functions -e _old_fish_prompt
        set -e _OLD_FISH_PROMPT_OVERRIDE
    end

    rm -f KONG_VENV_ENV_FILE
    set -e KONG_VENV KONG_VENV_ENV_FILE
    set -e LUAROCKS_CONFIG LUA_PATH LUA_CPATH KONG_PREFIX LIBRARY_PREFIX OPENSSL_DIR

    type -q stop_services && stop_services

    functions -e deactivate
    functions -e start_services
end

function start_services -d 'Start dependency services of Kong'
    source $workspace_path/scripts/dependency_services/up.fish
    # stop_services is defined by the script above
end


# actually set env vars
set -xg KONG_VENV_ENV_FILE (mktemp)
bash $KONG_VENV-venv/lib/venv-commons $KONG_VENV $KONG_VENV_ENV_FILE
source $KONG_VENV_ENV_FILE
set -xg PATH "$PATH"

# set shell prompt
if test -z "$KONG_VENV_DISABLE_PROMPT"
    # Copy the current `fish_prompt` function as `_old_fish_prompt`.
    functions -c fish_prompt _old_fish_prompt

    function fish_prompt
        # Run the user's prompt first; it might depend on (pipe)status.
        set -l prompt (_old_fish_prompt)

        # Prompt override provided?
        # If not, just prepend the environment name.
        if test -n ''
            printf '(%s) ' ''
        else
            printf '(%s) ' "$build_name"
        end

        string join -- \n $prompt # handle multi-line prompts
    end

    set -gx _OLD_FISH_PROMPT_OVERRIDE "$KONG_VENV"
end

if test -n "$argv"
    exec $argv
end
