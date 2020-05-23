#!/bin/sh

source_dir="$(cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P)"
mpv_script_dir="$HOME/.config/mpv/scripts"

# Delete existing install of MPV sponsorblock.
rm_install () {
    rm "$mpv_script_dir/sponsorblock.lua"
    rm -r "$mpv_script_dir/sponsorblock_shared"
}


# Install sponsorblock by copying files from git repo to MPV script directory.
install () {
    cp "$source_dir/sponsorblock.lua" "$mpv_script_dir/sponsorblock.lua"
    cp -r "$source_dir/sponsorblock_shared" "$mpv_script_dir/sponsorblock_shared"
}


main () {
    # Check if script directory exists, create it if it does not.
    if [ ! -d "$mpv_script_dir" ]; then
        printf "Created MPV script directory (~/.config/mpv/scripts).\n"
        mkdir -p "$mpv_script_dir"

    # Check if sponsorblock is already installed. If installed, ask if user wants to replace it.
    elif [ -f "$mpv_script_dir/sponsorblock.lua" ] || [ -d "$mpv_script_dir/sponsorblock_shared" ]; then
        printf "mpv_sponsorblock is already installed. Would you like to reinstall it? [y/n]: "
	while true; do
            read yn
            case $yn in
                [Yy]* ) rm_install && printf "Existing install removed\n"; break;;
                [Nn]* ) printf "Install aborted.\n"; exit;;
                * )  printf "Please enter 'y' for yes or 'n' for no: ";;
            esac
        done
    fi

    # Install
    install
    printf "Install complete\n"
}

main
