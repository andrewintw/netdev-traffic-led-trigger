#!/bin/sh

LED_PATH="/sys/class/leds/green"

# ===== Tunable parameters =====
POLL_US=200000	# Polling interval: 200ms
THRESHOLD=1	   # Highly sensitive packet delta threshold

# ===== ?? Usage and Argument Validation Line =====
show_usage() {
		echo "Usage: $(basename "$0") <interface1> [interface2] [interface3] ..."
		echo "Example: $(basename "$0") ath0 ath1"
		echo "Error: At least one network interface must be specified."
		exit 1
}

# Physical guard: If no arguments are passed ($# -eq 0), trigger usage and exit
if [ $# -eq 0 ]; then
		show_usage
fi

# Initialize dynamic previous-counters in memory using script-level variables
for iface in "$@"; do
		eval "p_${iface}_rx=0"
		eval "p_${iface}_tx=0"
done

current_mode="none"

set_led_mode() {
		mode="$1"
		[ "$current_mode" = "$mode" ] && return 0
		current_mode="$mode"

		case "$mode" in
				"idle")
						echo none > "$LED_PATH/trigger"
						echo 255 > "$LED_PATH/brightness"
						;;
				"traffic")
						echo timer > "$LED_PATH/trigger"
						echo 20 > "$LED_PATH/delay_on"
						echo 30 > "$LED_PATH/delay_off"
						;;
		esac
}

set_led_mode "idle"

# ===== Main Loop (Dynamic Interface Polling Pipeline) =====
while true; do
		total_delta=0

		# Dynamic Loop: Iterate through all arguments passed to the script ($1, $2, ...)
		for iface in "$@"; do
				# Pure built-in 'read' bypasses 'cat' binary fork for high performance
				if read -r c_rx < "/sys/class/net/$iface/statistics/rx_packets" 2>/dev/null && \
				   read -r c_tx < "/sys/class/net/$iface/statistics/tx_packets" 2>/dev/null; then

						# Retrieve previous counters via eval mapping
						eval "p_rx=\$p_${iface}_rx"
						eval "p_tx=\$p_${iface}_tx"

						# Calculate individual deltas
						dr=$((c_rx - p_rx))
						dt=$((c_tx - p_tx))

						# Handle interface wrap-around or provisional resets
						[ $dr -lt 0 ] && dr=0
						[ $dt -lt 0 ] && dt=0

						# Accumulate total traffic delta across all active interfaces
						total_delta=$((total_delta + dr + dt))

						# Rotate counters for this specific interface
						eval "p_${iface}_rx=$c_rx"
						eval "p_${iface}_tx=$c_tx"
				fi
		done

		# ===== Hardware Execution Matrix =====
		if [ "$total_delta" -ge "$THRESHOLD" ]; then
				set_led_mode "traffic"
		else
				set_led_mode "idle"
		fi

		usleep "$POLL_US"
done
