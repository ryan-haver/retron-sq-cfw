DUMPER_PATH="/media/usb0/"
SDCARD_BASE="/mnt/roms"
NAND_FALLBACK="/userdata/rom"

# RetroArch standard folder names
FOLDER_GB="Nintendo - Game Boy"
FOLDER_GBC="Nintendo - Game Boy Color"
FOLDER_GBA="Nintendo - Game Boy Advance"

# Determine if SD card is available
USE_SDCARD=0
if [ -d "$SDCARD_BASE" ]; then
    USE_SDCARD=1
    echo "Using SD card storage: $SDCARD_BASE" > /dev/console
else
    mkdir -p "$NAND_FALLBACK" 2>/dev/null
    echo "WARNING: SD card not found, using NAND: $NAND_FALLBACK" > /dev/console
fi

# Get ROM path based on file extension
GetRomPath() {
    local filename="$1"
    local ext="${filename##*.}"
    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
    
    if [ "$USE_SDCARD" = "1" ]; then
        case "$ext" in
            gba)
                echo "$SDCARD_BASE/$FOLDER_GBA"
                ;;
            gbc)
                echo "$SDCARD_BASE/$FOLDER_GBC"
                ;;
            gb)
                echo "$SDCARD_BASE/$FOLDER_GBC"
                ;;
            *)
                echo "$SDCARD_BASE/$FOLDER_GBC"
                ;;
        esac
    else
        echo "$NAND_FALLBACK"
    fi
}

# Find ROM in any system folder
FindRomPath() {
    local filename="$1"
    local path=""
    
    if [ "$USE_SDCARD" = "1" ]; then
        # Check system folders on SD card
        if [ -f "$SDCARD_BASE/$FOLDER_GBA/$filename" ]; then
            echo "$SDCARD_BASE/$FOLDER_GBA"
            return
        fi
        if [ -f "$SDCARD_BASE/$FOLDER_GBC/$filename" ]; then
            echo "$SDCARD_BASE/$FOLDER_GBC"
            return
        fi
        if [ -f "$SDCARD_BASE/$FOLDER_GB/$filename" ]; then
            echo "$SDCARD_BASE/$FOLDER_GB"
            return
        fi
    fi
    
    # Fallback to NAND
    if [ -f "$NAND_FALLBACK/$filename" ]; then
        echo "$NAND_FALLBACK"
        return
    fi
    
    # Return expected path for new file
    GetRomPath "$filename"
}

RETROARCH_BIN="/usr/bin/retroarch"
RETROARCH_CON="/userdata/retroarch/retroarch.cfg"
GBA_PLUGIN="/usr/lib/libretro/gpsp_libretro.so"
GB_PLUGIN="/usr/lib/libretro/vbam_libretro.so"
MGBA_PLUGIN="/usr/lib/libretro/mgba_libretro.so"
HOME="/userdata"

if [ ! -f "/tmp/rom.txt" ]; then
	PREROM=""
else
	source "/tmp/rom.txt"
fi

function CheckROM(){
	cd "${DUMPER_PATH}"
	for file in *.gb *.gbc *.gba
	do
		if [ -f "${file}" ]; then
			echo "${file}"
			return
		fi
	done
}


function KillGame(){
	killall retroarch
	/bin/sync
}

function ResetROM(){
	if pidof "retroarch" > /dev/null; then
		echo "kill retroarch" > /dev/console
		/usr/bin/killall -9 retroarch
	fi
	result=$(CheckROM)
	if [[ "x$result" == "x" ]]; then
		echo "No cartridge in USB, launching menu" > /dev/console
		# CFW: Keep dumped ROMs for cartless play - don't delete PREROM
		# User can browse to system folders to play previously dumped games
		HOME=$HOME $RETROARCH_BIN -v -c $RETROARCH_CON --menu > /dev/console 2>&1 &
	else
		if  pidof "hyperkin-loading" > /dev/null; then
			echo "Now executing the hyperkin-loading" > /dev/console
			echo "Disabled reset function until hyperkin-loading finished." > /dev/console
		else
			local rom_folder=$(GetRomPath "$result")
			local rom_fullpath="$rom_folder/$result"
			echo "New cart detected, will dump to: $rom_fullpath" > /dev/console
			
			# Remove old copy if switching carts
			if [ -f "$rom_fullpath" ]; then
				/bin/rm -rf "$rom_fullpath"
			fi
			echo 3 > /proc/sys/vm/drop_caches
			/usr/bin/hyperkin-loading > /dev/console
			/bin/sync
			
			result=$(CheckROM)
			if [[ "x$result" != "x" ]]; then
				rom_folder=$(FindRomPath "$result")
				rom_fullpath="$rom_folder/$result"
				echo "PREROM=\"$rom_fullpath\"" > /tmp/rom.txt
				
				is_gba=$(echo "$result" | grep -i ".gba")
				if [[ "x$is_gba" != "x" ]]; then
					if [ -f /userdata/gb.txt ] && [ $(grep -c "$result" /userdata/gb.txt 2>/dev/null) -eq 1 ]; then
						echo "loading: $rom_fullpath (mGBA)" > /dev/console
						HOME=$HOME $RETROARCH_BIN -v -c $RETROARCH_CON -L $MGBA_PLUGIN "$rom_fullpath" > /dev/console 2>&1 &
					else
						HOME=$HOME $RETROARCH_BIN -v -c $RETROARCH_CON -L $GBA_PLUGIN "$rom_fullpath" > /dev/console 2>&1 &
					fi
				else
					if [ -f /userdata/gb.txt ] && [ $(grep -c "$result" /userdata/gb.txt 2>/dev/null) -eq 1 ]; then
						echo "loading: $rom_fullpath (mGBA)" > /dev/console
						HOME=$HOME $RETROARCH_BIN -v -c $RETROARCH_CON -L $MGBA_PLUGIN "$rom_fullpath" > /dev/console 2>&1 &
					else
						HOME=$HOME $RETROARCH_BIN -v -c $RETROARCH_CON -L $GB_PLUGIN "$rom_fullpath" > /dev/console 2>&1 &
					fi
				fi
			else
				echo "No Cartridge" > /dev/console
			fi
		fi
	fi
}

function RunGame(){
if pidof "retroarch" > /dev/null; then
	echo "retroarch already running" > /dev/console
else
	echo "retroarch not running" > /dev/console
	result=$(CheckROM)
	if [[ "x$result" == "x" ]]; then
		echo "No cartridge detected, launching RetroArch menu" > /dev/console
		HOME=$HOME $RETROARCH_BIN -v -c $RETROARCH_CON --menu > /dev/console 2>&1 &
	else
		local rom_folder=$(FindRomPath "$result")
		local rom_fullpath="$rom_folder/$result"
		
		if [ ! -f "$rom_fullpath" ]; then
			# File not found, start copy
			echo "Copying ROM to: $rom_fullpath" > /dev/console
			/usr/bin/hyperkin-loading > /dev/console
		else
			/usr/bin/hyperkin-crc "$rom_fullpath" > /dev/console
			retval=$?
			echo "CRC check retval=$retval" > /dev/console
			if [ $retval -ne 0 ]; then
				echo "ROM CRC check fail, copying again" > /dev/console
				/usr/bin/hyperkin-loading > /dev/console
			else
				echo "ROM CRC check passed" > /dev/console
			fi
		fi
		/bin/sync
		
		result=$(CheckROM)
		if [[ "x$result" != "x" ]]; then
			rom_folder=$(FindRomPath "$result")
			rom_fullpath="$rom_folder/$result"
			echo "PREROM=\"$rom_fullpath\"" > /tmp/rom.txt
			
			is_gba=$(echo "$result" | grep -i ".gba")
			if [[ "x$is_gba" != "x" ]]; then
				if [ -f /userdata/gb.txt ] && [ $(grep -c "$result" /userdata/gb.txt 2>/dev/null) -eq 1 ]; then
					echo "loading: $rom_fullpath (mGBA)" > /dev/console
					HOME=$HOME $RETROARCH_BIN -v -c $RETROARCH_CON -L $MGBA_PLUGIN "$rom_fullpath" > /dev/console 2>&1 &
				else
					# RetroArch handles saves automatically - no symlink needed
					HOME=$HOME $RETROARCH_BIN -v -c $RETROARCH_CON -L $GBA_PLUGIN "$rom_fullpath" > /dev/console 2>&1 &
				fi
			else
				if [ -f /userdata/gb.txt ] && [ $(grep -c "$result" /userdata/gb.txt 2>/dev/null) -eq 1 ]; then
					echo "loading: $rom_fullpath (mGBA)" > /dev/console
					HOME=$HOME $RETROARCH_BIN -v -c $RETROARCH_CON -L $MGBA_PLUGIN "$rom_fullpath" > /dev/console 2>&1 &
				else
					HOME=$HOME $RETROARCH_BIN -v -c $RETROARCH_CON -L $GB_PLUGIN "$rom_fullpath" > /dev/console 2>&1 &
				fi
			fi
		fi
	fi
fi
}
