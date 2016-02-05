#!/usr/bin/env bash
#
# Post Install Script for Ubuntu 15.10 with Gnome 3.16
#
# This file:
#  - Functions for the installation processes
#
# More info:
#  - https://github.com/oengusmacinog/ubuntu-post-install
#
# Version 1.0.0
#
# Authors:
#  - Brian Garland (http://brigarland.io)
#

# Apt-Get Installation
# ##################################################
# Usage:
#    install_package [dpkg name] [opt title str]
# ##################################################
install_package() {

	#Trim extra white space from end of file gatherd app names
	local pkg=$(echo "$1" | trim)

	# If better formatted names are accessable use them for messages
	[ -n "${TITLE_INFO[$pkg]}" ] && local pkg_title=$(echo "${TITLE_INFO[$pkg]}" | trim) || local pkg_title="$1"

	set +o errexit

	# Check if package is installed
	if dpkg_installed "$pkg"; then
		emes infpos $pkg_title
		return
	fi

	emes actpos 'Installing' $pkg_title

	apt-get install -q -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" "$pkg" >> $TMP_DIR/temp_output.log 2>&1 &
    progress_spinner $!
    econ check dpkg_installed $1

	set -o errexit

}

# Downloadable Deb Installation
install_deb() {
	#Trim extra white space from end of file gatherd app names
	local pkg=$(echo "$1" | trim)

	# If better formatted names are accessable use them for messages
	[ -n "${TITLE_INFO[$pkg]}" ] && local pkg_temp=$(echo "${TITLE_INFO[$pkg]}" | trim) || local pkg_temp="$1"

	# Get link to grab deb package from
	[ -n "${LINK_INFO[$pkg]}" ] && local pkg_url=$(echo "${LINK_INFO[$pkg]}" | trim) || return

	if [[ "$str" != "${str%[[:]]*}" ]]; then
		pkg_title=$pkg_temp
	else
		pkg_infos=()
		pkg_title=${pkg_temp%%:*}
		pkg_temp=${pkg_temp#*:}
		while true ; do
		    pkg_info=${pkg_temp%%:*}
		    pkg_temp=${pkg_temp#*:}
		    pkg_infos[i++]=$pkg_info
		    # We are done when there is no more colon
		    if test "$pkg_temp" = "$pkg_info" ; then
		        break
		    fi
		done
	fi

	set +o errexit

	# Check if package is installed
	if dpkg_installed "$pkg"; then
		emes infpos $pkg_title
		return
	fi

	emes actpos 'Downloading' "$pkg_title" "${pkg_infos[0]}" "${pkg_infos[1]}" "${pkg_infos[2]}"
	nosudo wget "$pkg_url" -qO mktemp >> $TMP_DIR/temp_output.log 2>&1 &
	progress_spinner $!
	econ check is_file 'mktemp'

	emes extrapos 'Installing' '' '' '                        ⮱  '
	dpkg -i mktemp >> $TMP_DIR/temp_output.log 2>&1 &
	progress_spinner $!

	econ check dpkg_installed $1

	rm mktemp

	set -o errexit

}

install_codecs() {
	# Pre-accept the terms
	# debconf-set-selections <<< "ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true"
    install_package 'ubuntu-restricted-extras'
}

install_lamp() {

	lamp_graphic
	mapfile -t LAMPLIST < <(tasksel --task-packages lamp-server)
	for i in "${LAMPLIST[@]}"; do
       	install_package $i
    done

}

# Apache Mods
install_apachemods() {

	emes extrapos 'Enabling' 'Apache Rewrite mod' '' ''
	a2enmod rewrite >> $TMP_DIR/temp_output.log 2>&1 &
	progress_spinner $!
	esuc -i

}

#PHP Mods
install_phpmods() {

	local restart=false

	for mod in ${PHP_MODS[@]}; do
		if dpkg_installed "$mod"; then
			emes infpos $mod 'PHP mod is already installed'
		else
			echo "\$mod: $mod"
		  	emes actpos 'Installing' $mod '' 'PHP mod'
	   	 	apt-get install -q -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" "$mod" >> $TMP_DIR/temp_output.log 2>&1 &
	   	 	progress_spinner $!
	   	 	econ check dpkg_installed $mod
	   	 	restart=true
	   	 	if [ "$mod" == "php5-mcrypt" ]; then
	   	 		emes extrapos 'Enabling ' 'php5-mcrypt' '' ''
				php5enmod mcrypt >> $TMP_DIR/temp_output.log 2>&1 &
				nbsp
				esuc -i
	   	 	fi
		fi

	done

	if $restart; then
		emes extrapos 'Restarting ' 'Apache' '' ''
		service apache2 restart >> $TMP_DIR/temp_output.log 2>&1 &
		nbsp
		esuc -i
	fi

}
# Install Composer
install_composer() {

	if is_file "$COMPOSER_PATH/composer"; then
		emes infpos "Composer"
		return
	else
		emes actpos 'Installing' 'Composer' '' 'PHP' 'dependency manager'
		nosudo curl -sS https://getcomposer.org/installer | php >> $TMP_DIR/temp_output.log 2>&1 &
		echo this
		mv composer.phar "$COMPOSER_PATH/composer" >> $TMP_DIR/temp_output.log 2>&1 &
		progress_spinner $!
		econ check is_file "$COMPOSER_PATH/composer"
	fi

}

# Espresso
install_espresso() {

	if is_file "$ESPRESSO_PATH/espresso"; then
		emes infpos "Espresso"
		return
	else

		emes extrapos 'Downloading' 'Git Repository' '' ''

		nosudo git clone https://github.com/caffeinated/espresso.git $ESPRESSO_PATH >> $TMP_DIR/temp_output.log 2>&1 &
		progress_spinner $!
        econ check is_file "$ESPRESSO_PATH/espresso"

		cd $ESPRESSO_PATH/www

		emes extrapos 'Running' 'Composer' '' '' 'project build'

		nosudo composer install >> $TMP_DIR/temp_output.log 2>&1 &
		progress_spinner $!
		esuc -i
		# econ check is_file $ESPRESSO_PATH

		cd $SCRIPT_PATH

	fi

}

# Sublime Package Control
install_sublime_pc() {

	# Check if Sublime is Installed
	dpkg_not_installed sublime-text-installer && die "Sublime Text 3 not installed" || true

	# Check if Package Control is already installed
	if is_dir "$HOME/.config/sublime-text-3/Installed\ Packages"; then
		emes infpos 'Sublime Text 3' '' 'Package Control'
		return
	else
		emes header 'Setting up' 'Sublime Text' 'lightweight code editor'
		emes actpos 'Installing' 'Sublime Text 3' '' 'Package Control'
		wget -qP "$HOME/.config/sublime-text-3/Installed\ Packages http://packagecontrol.io/Package%20Control.sublime-package" >> "$TMP_DIR/temp_output.log" 2>&1 &
		progress_spinner $!
		econ check is_dir "$HOME/.config/sublime-text-3/Installed Packages"
	fi

	# emes config 'Sublime Text 3'

    # Install License Key
    # sudo -u $SUDO_USER cp $__dir__/resources/License.sublime_license $HOME/.config/sublime-text-3/Local/License.sublime_license

    emes extraconf 'Configuring' 'Packages'

    # Move Package Control settings with list of Packages to the config folder
    cp "$SCRIPT_PATH/opt/sublime/Package\ Control.sublime-settings" "$HOME/.config/sublime-text-3/Packages/User/Package\ Control.sublime-settings"

}

install_ohmyzsh() {

	emes actpos 'Installing the' 'Z Shell'
	check_dependencies dpkg zsh curl git
	nosudo sh -c "$(curl -fsSL https://raw.github.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"
	esuc -i

}

install_powerline() {

	emes actpos 'Installing' 'Powerline' ', a terminal style tool'

	check_dependencies dpkg python-pip git

	su -c 'pip install git+git://github.com/Lokaltog/powerline'

	nosudo wget https://github.com/Lokaltog/powerline/raw/develop/font/PowerlineSymbols.otf https://github.com/Lokaltog/powerline/raw/develop/font/10-powerline-symbols.conf
	mv PowerlineSymbols.otf /usr/share/fonts/
	fc-cache -vf
	mv 10-powerline-symbols.conf /etc/fonts/conf.d/

	# Bash
	printf '%s\n\t%s\n%s' 'if [ -f /usr/local/lib/python2.7/dist-packages/powerline/bindings/bash/powerline.sh ]; then' 'source /usr/local/lib/python2.7/dist-packages/powerline/bindings/bash/powerline.sh' 'fi' >> /etc/bash.bashrc

	# Zsh
	printf '%s\n\t%s\n%s' 'if [[ -r /usr/local/lib/python2.7/dist-packages/powerline/bindings/zsh/powerline.zsh ]]; then' 'source /usr/local/lib/python2.7/dist-packages/powerline/bindings/zsh/powerline.zsh' 'fi' >> /etc/zsh/zshrc

}

# Repositories Installation

repo_cleaner() {
	if is_file "$APT_SRCLIST_PATH/$1"; then
		safe_rm "$APT_SRCLIST_PATH/$1"
		safe_rm "$APT_SRCLIST_PATH/$1.save"
		emes actpos 'Updating' $2 $3 $4
	else
		emes actpos 'Adding' $2 $3 $4
	fi
}

# UB_CODENAME
# add_launchpad_repo() {
#
# }
#
# add_deb_repo() {
#
# }

install_ppa() {
	emes actpos "Updating" "${3}" "PPA" "from" "${2}"
	add-apt-repository -y "ppa:${2}/${1}"  >> $TMP_DIR/temp_output.log 2>&1 &
	progress_spinner $!
	esuc -i
}


install_repo() {

	econ needsudo

    case $1 in

        *Chrome*|*chrome*)
        	repo_cleaner 'google-chrome.list' 'Google Chrome' 'PPA'

		    nosudo wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add - >> $TMP_DIR/temp_output.log 2>&1 &
		    sh -c 'echo "deb https://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google-chrome.list'  >> $TMP_DIR/temp_output.log 2>&1 &
			progress_spinner $!

			econ check repo_installed 'google-chrome.list'
            ;;

        *Sublime*|*sublime*)
        	repo_cleaner 'webupd8team-ubuntu-sublime-text-3-wily.list' 'Sublime Text 3' 'PPA'

		    add-apt-repository -y "ppa:webupd8team/sublime-text-3" >> $TMP_DIR/temp_output.log 2>&1 &
			progress_spinner $!

			econ check repo_installed 'webupd8team-ubuntu-sublime-text-3-wily.list'
            ;;

        *Yorba*|*yorba*)
        	emes actneg 'Yorba repository' 'is not currently supported on' 'Wily' 'The'
        	eerr -i
            ;;

        *Rabbit*|*rabbit*)
        	repo_cleaner 'getdeb.list' 'Getdeb' 'Repository' 'for RabbitVCS'

		    nosudo wget -q -O - http://archive.getdeb.net/getdeb-archive.key | sudo apt-key add - >> $TMP_DIR/temp_output.log 2>&1 &
		    sh -c 'echo "deb http://archive.getdeb.net/ubuntu vivid-getdeb apps" >> /etc/apt/sources.list.d/getdeb.list' >> $TMP_DIR/temp_output.log 2>&1 &
			progress_spinner $!

			econ check repo_installed 'getdeb.list'
            ;;

        *Gimp*|*gimp*)
        	repo_cleaner 'otto-kesselgulasch-ubuntu-gimp-wily.list' 'Otto Kesselgulasch' 'PPA' 'for GIMP'

		    add-apt-repository -y "ppa:otto-kesselgulasch/gimp" >> $TMP_DIR/temp_output.log 2>&1 &
			progress_spinner $!

			econ check repo_installed 'otto-kesselgulasch-ubuntu-gimp-wily.list'
            ;;

        *Node*|*node*)
        	repo_cleaner 'nodesource.list' 'NodeJS' 'Project Repository' 'v5.x'

			check_dependencies dpkg curl

		    nosudo curl --silent --location https://deb.nodesource.com/setup_5.x | bash - >> $TMP_DIR/temp_output.log 2>&1 &
		    progress_spinner $!

			econ check repo_installed 'nodesource.list'
            ;;

        *Spotify*|*spotify*)
        	repo_cleaner 'spotify.list' 'Spotify' 'Repository'

		    apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys BBEBDCB318AD50EC6865090613B00F1FD2C19886 >> $TMP_DIR/temp_output.log 2>&1 &
		    sudo sh -c 'echo "deb http://repository.spotify.com stable non-free" >> /etc/apt/sources.list.d/spotify.list' >> $TMP_DIR/temp_output.log 2>&1 &
		    progress_spinner $!

			econ check repo_installed 'spotify.list'
            ;;

        *Numix*|*numix*)
        	repo_cleaner 'numix-ubuntu-ppa-wily.list' 'Numix' 'PPA'

		    	apt-add-repository -y ppa:numix/ppa >> $TMP_DIR/temp_output.log 2>&1 &
		    	progress_spinner $!

					econ check repo_installed " numix-ubuntu-ppa-$UB_CODENAME.list"
            ;;
						# *Universe*|*universe*)
						# 	deb http://us.archive.ubuntu.com/ubuntu/ $UB_CODENAME universe" >> /etc/apt/sources.list.d/ubuntu_universe_updates.list) >> $TMP_DIR/temp_output.log 2>&1 &
						# 	deb-src http://us.archive.ubuntu.com/ubuntu/ $UB_CODENAME universe" >> /etc/apt/sources.list.d/ubuntu_universe_updates.list) >> $TMP_DIR/temp_output.log 2>&1 &
						# 	deb http://us.archive.ubuntu.com/ubuntu/ $UB_CODENAME-updates universe" >> /etc/apt/sources.list.d/ubuntu_universe_updates.list) >> $TMP_DIR/temp_output.log 2>&1 &
						# 	deb-src http://us.archive.ubuntu.com/ubuntu/ $UB_CODENAME-updates universe" >> /etc/apt/sources.list.d/ubuntu_universe_updates.list) >> $TMP_DIR/temp_output.log 2>&1 &
						# ;;
						# *Multiverse*|*multiverse*)
						# 	deb http://us.archive.ubuntu.com/ubuntu/ $UB_CODENAME multiverse" >> /etc/apt/sources.list.d/canonical_partner.list) >> $TMP_DIR/temp_output.log 2>&1 &
						# 	deb-src http://us.archive.ubuntu.com/ubuntu/ $UB_CODENAME multiverse" >> /etc/apt/sources.list.d/canonical_partner.list) >> $TMP_DIR/temp_output.log 2>&1 &
						# 	deb http://us.archive.ubuntu.com/ubuntu/ $UB_CODENAME-updates multiverse" >> /etc/apt/sources.list.d/canonical_partner.list) >> $TMP_DIR/temp_output.log 2>&1 &
						# 	deb-src http://us.archive.ubuntu.com/ubuntu/ $UB_CODENAME-updates multiverse" >> /etc/apt/sources.list.d/canonical_partner.list) >> $TMP_DIR/temp_output.log 2>&1 &
						# 	;;
						*Verses*|*verses*|*Universe*|*universe*|*Multiverse*|*multiverse*)
							sudo add-apt-repository "deb http://us.archive.ubuntu.com/ubuntu/ $UB_CODENAME universe multiverse"
							sudo add-apt-repository "deb http://us.archive.ubuntu.com/ubuntu/ $UB_CODENAME-updates universe multiverse"
							;;
						*Partners*|*partners*)
							$(echo "deb http://archive.canonical.com/ubuntu $UB_CODENAME partner" >> /etc/apt/sources.list.d/canonical_partner.list) >> $TMP_DIR/temp_output.log 2>&1 &
							$(echo "deb-src http://archive.canonical.com/ubuntu $UB_CODENAME partner" >> /etc/apt/sources.list.d/canonical_partner.list) >> $TMP_DIR/temp_output.log 2>&1 &
							;;
						*Gnome*|*gnome*)

							add-apt-repository -y "ppa:gnome3-team/gnome3" >> $TMP_DIR/temp_output.log 2>&1 &
							add-apt-repository -y "ppa:gnome3-team/gnome3-staging" >> $TMP_DIR/temp_output.log 2>&1 &
							# $(echo "deb http://ppa.launchpad.net/gnome3-team/gnome3/ubuntu wily main" >> /etc/apt/sources.list.d/gnome3.list) >> $TMP_DIR/temp_output.log 2>&1 &
							# $(echo "deb http://ppa.launchpad.net/gnome3-team/gnome3/ubuntu $UB_CODENAME main" >> /etc/apt/sources.list.d/gnome3.list) >> $TMP_DIR/temp_output.log 2>&1 &
							# $(echo "deb-src http://ppa.launchpad.net/gnome3-team/gnome3/ubuntu $UB_CODENAME main" >> /etc/apt/sources.list.d/gnome3.list) >> $TMP_DIR/temp_output.log 2>&1 &
							# $(echo "deb http://ppa.launchpad.net/gnome3-team/gnome3-staging/ubuntu $UB_CODENAME main" >> /etc/apt/sources.list.d/gnome3-staging.list) >> $TMP_DIR/temp_output.log 2>&1 &
							# $(echo "deb-src http://ppa.launchpad.net/gnome3-team/gnome3-staging/ubuntu $UB_CODENAME main" >> /etc/apt/sources.list.d/gnome3-staging.list) >> $TMP_DIR/temp_output.log 2>&1 &
						;;
        * )
			emes actneg "$1 repository" 'currently not supported' '' "I\'m sorry,"
			eerr -i
            ;;

    esac

}

gnome_extension_install() {

  # echo ${TMP_DIR}

  local extension_name=$1
  # local extension_id=815
  # local extension_info_url="https://extensions.gnome.org/extension-info/?pk=$extension_id&shell_version=$GS_VERSION"
  # local extension_download_url=1
  # local extension_uuid=1
  local old_extensions=$(gsettings get org.gnome.shell enabled-extensions)
  # echo ${GNOME_EXT_IDS[s$1]}

  wget -q -O "${TMP_DIR}/temp-${1}" "https://extensions.gnome.org/extension-info/?pk=${GNOME_EXT_IDS[$1]}&shell_version=$GS_VERSION"
  # wget -q -O $TMP_DIR/temp "https://extensions.gnome.org/extension-info/?pk=$extension_id&shell_version=$GS_VERSION"

  local extension_uuid=$(cat "${TMP_DIR}/temp-${1}" | sed 's/.* "//' | sed 's/"}//')

  # local extension_uuid='apps-menu@gnome-shell-extensions.gcampax.github.com'
  local extension_download_url="https://extensions.gnome.org$(cat "${TMP_DIR}/temp-${1}" | sed 's/.*download_url": "//' | sed 's/", ".*//')"
  #
  # # echo $extension_download_url
  #
  wget -O "${TMP_DIR}/extension-${1}.zip" "${extension_download_url}"
  mkdir -p "$HOME/.local/share/gnome-shell/extensions/$extension_uuid"
  unzip "${TMP_DIR}/extension-${1}.zip" -d "$HOME/.local/share/gnome-shell/extensions/$extension_uuid"
	# rm "${TMP_DIR}/extension.zip"

  if is_not_in_str "$extension_uuid" "$old_extensions"; then
    # echo "It's not there!"
    local new_extensions=$(echo $old_extensions | sed "s/']/', '$extension_uuid']/")
	# elif is_in_str "[]" "$old_extensions"; then
	# 	local new_extensions=$(echo $old_extensions | sed "s//['$extension_uuid']/")
		#statements
  else
	# 	local new_extensions='[]'
    echo "It is there!"
  fi
  echo $new_extensions
##Not setting correctly
  gsettings set org.gnome.shell enabled-extensions "$new_extensions"

  # gnome-shell --replace &
}

# Update sources
apt_update() {
    eart -bn --c=120 "Updating"
    eart -bn --c=159 " sources"
    ekho -n "... "

    set +o errexit

    apt-get -qq -y update >> $TMP_DIR/temp_output.log 2>&1 &
    local pid=$!
		progress_spinner $!

		esuc -i

    set -o errexit
}

# Update sources
apt_upgrade() {
    eart -bn --c=120 "Upgrading"
    eart -bn --c=159 " packages"
    ekho -n "... "

    set +o errexit

    apt-get -qq -y upgrade >> $TMP_DIR/temp_output.log 2>&1 &
    local pid=$!
		progress_spinner $!

		esuc -i

    set -o errexit
}

apt_dist_upgrade() {
    eart -bn --c=120 "Upgrading"
    eart -bn --c=159 " distribution"
    ekho -n "... "

    set +o errexit

    apt-get -qq -y dist-upgrade >> $TMP_DIR/temp_output.log 2>&1 &
    local pid=$!
		progress_spinner $!

		esuc -i

    set -o errexit

		# reboot
}