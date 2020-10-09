#!/bin/bash

# Teal Dulcet
# Benchmarking tool
# Adapted from hyperfine: https://github.com/sharkdp/hyperfine
# Run: ./time.sh [OPTIONS] <command(s)>...

# set -e

# Set the variables below

# Number of warmup runs before the actual benchmark
WARMUP=0
# Minimum number of runs for each command
MINRUNS=''
# Maximum number of runs for each command
MAXRUNS=''
# Exact number of runs for each command
RUNS=''

# Command(s)
COMMANDS=(

)

# Prepare command(s) to execute before each run
PREPARE=(

)
# Cleanup command to execute after all runs for each command
CLEANUP=''

# Ignore-failure
# FAILURE=1

# Export CSV
# CSV=table.csv
# Export JSON
# JSON=table.json

# bar_length=40

# Use Unicode characters in output
UNICODE=1
# Interactive output
INTERACTIVE=1

# Default minimum number of runs
MIN=10
# Minimum benchmarking time (seconds)
MINTIME=3
# Threshold for warning about fast execution time (seconds)
MINEXECUTIONTIME=0.005
# Minimum modified Z-score for a datapoint to be an outlier
OUTLIERTHRESHOLD=14.826 # 1.4826 * 10.0

# Do not change anything below this

RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
BLUE='\e[34m'
MAGENTA='\e[35m'
CYAN='\e[36m'
BOLD='\e[1m'
DIM='\e[2m'
NC='\e[m' # No Color

# Check if on Linux
if ! echo "$OSTYPE" | grep -iq "linux"; then
	echo "Error: This script must be run on Linux." >&2
	exit 1
fi

# Output usage
# usage <programname>
usage() {
	echo "Usage:  $1 [OPTION(S)] <command(s)>...
or:     $1 <OPTION>
All the options can also be set by opening the script in an editor and setting the variables at the top. See examples below.

Options:
    -w <NUM>        Warmup
                        Perform NUM warmup runs before the actual benchmark. This can be used to fill (disk) caches for I/O-heavy programs. Default: $WARMUP
    -m <NUM>        Min-runs
                        Perform at least NUM runs for each command. Default: ${MINRUNS:-$MIN}
    -M <NUM>        Max-runs
                        Perform at most NUM runs for each command. Default: ${MAXRUNS:-no limit}
    -r <NUM>        Runs
                        Perform exactly NUM runs for each command. If this option is not specified, it will automatically determines the number of runs.
    -p <command>    Prepare
                        Execute command before each run. This is useful for clearing disk caches, for example. The prepare option can be specified once for all commands or multiple times, once for each command. In the latter case, each preparation command will be run prior to the corresponding benchmark command.
    -c <command>    Cleanup
                        Execute command after the completion of all benchmarking runs for each individual command to be benchmarked. This is useful if the commands to be benchmarked produce artifacts that need to be cleaned up.
    -i              Ignore-failure
                        Ignore non-zero exit codes of the benchmarked programs.
    -u              ASCII
                        Do not use Unicode characters in output.
    -s              Disable interactive
                        Disable interactive output and progress bars.
    -C <FILE>       Export CSV
                        Export the timing summary statistics as CSV to the given FILE.
    -j <FILE>       Export JSON
                        Export the timing summary statistics and timings of individual runs as JSON to the given FILE.
    -h              Display this help and exit
    -v              Output version information and exit

Examples:
    Basic benchmark
    $ $1 'sleep 0.3'

    Benchmark two commands
    $ $1 'find -iname \"*.jpg\"' 'fd -e jpg -uu'

    Benchmark piped commands
    $ $1 'seq 0 10000000 | factor' 'seq 0 10000000 | uu-factor'

    Warmup runs
    $ $1 -w 3 'grep -R TODO *'

    Parameterized benchmark
    $ $1 -p 'make clean' 'make -j '{1..12}
    This performs benchmarks for 'make -j 1', 'make -j 2', … 'make -j 12'.

    Parameterized benchmark with step size
    $ $1 'sleep 0.'{3..7..2}
    This performs benchmarks for 'sleep 0.3', 'sleep 0.5' and 'sleep 0.7'.

    Parameterized benchmark with list
    $ $1 {gcc,clang}' -O3 main.c'
    This performs benchmarks for 'gcc -O3 main.c' and 'clang -O3 main.c'.
" >&2
}

if [[ $# -eq 0 ]]; then
	usage "$0"
	exit 1
fi

while getopts "c:hij:m:p:r:suvw:C:M:" c; do
	case ${c} in
	c )
		CLEANUP=$OPTARG
	;;
	h )
		usage "$0"
		exit 0
	;;
	i )
		FAILURE=1
	;;
	j )
		JSON=$OPTARG
	;;
	m )
		MINRUNS=$OPTARG
	;;
	p )
		PREPARE+=( "$OPTARG" )
	;;
	r )
		RUNS=$OPTARG
	;;
	s )
		INTERACTIVE=''
	;;
	u )
		UNICODE=''
	;;
	v )
		echo -e "Bash Benchmark 1.0\n"
		exit 0
	;;
	w )
		WARMUP=$OPTARG
	;;
	C )
		CSV=$OPTARG
	;;
	M )
		MAXRUNS=$OPTARG
	;;
	\? )
		echo -e "Try '$0 -h' for more information.\n" >&2
		exit 1
	;;
	esac
done
shift $((OPTIND - 1))

if [[ $# -eq 0 ]]; then
	usage "$0"
	exit 1
fi

decimal_point=$(locale decimal_point)

COMMANDS+=( "$@" )

if [[ -n "$INTERACTIVE" ]]; then
	if ! [ -t 1 ]; then
		INTERACTIVE=''
	fi
fi

# error <message>
error() {
	printf "${RED}Error${NC}: %s\n" "$1" >&2
	exit 1
}

# warning <message>
warning() {
	printf "${YELLOW}Warning${NC}: %s\n\n" "$1"
}

# Progress bar
# Adapted from: https://github.com/dylanaraps/pure-bash-bible#progress-bars
# bar <progress percentage (0-100)> [label] [color]
bar() {
	local text length label abar_length usage prog total
	WIDTH=${COLUMNS:-$(tput cols)}
	# https://stackoverflow.com/a/30938702
	text=$(echo "${2}" | sed 's/'$'\x1B''\[\([0-9]\+\(;[0-9]\+\)*\)\?[mKHfJ]//g')
	((length=30 + ${#2} - ${#text}))
	
	if [[ -z "$UNICODE" ]]; then
		label="$(printf "%.1f" "${1/./$decimal_point}")%"
		abar_length=${bar_length:-$((WIDTH < 43 ? 10 : WIDTH - 33))}
		# ((usage=$1 * abar_length / 100))
		usage=$(echo "$1 $abar_length" | awk '{ printf "%d", $1 * $2 / 100 }')

		# Create the bar with spaces.
		if [[ ${#label} -gt $((abar_length - usage)) ]]; then
			printf -v prog  "%$(( abar_length - ${#label} ))s"
			total=''
		else
			printf -v prog  "%${usage}s"
			printf -v total "%$(( abar_length - usage - ${#label} ))s"
		fi

		output="${prog// /|}${total}${label}"
		printf "\e[K%-*s [${3}%s${3:+${NC}}%s]\r" "$length" "${2}" "${output::$usage}" "${output:$usage}"
	else
		label="$(printf "%5.1f" "${1/./$decimal_point}")%"
		abar_length=${bar_length:-$((WIDTH < 50 ? 10 : WIDTH - 40))}
		((abar_length*=8))
		usage=$(echo "$1 $abar_length" | awk '{ printf "%d", $1 * $2 / 100 }')

		# Create the bar with spaces.
		printf -v prog  "%$(( usage / 8 ))s"
		printf -v total "%$(( (abar_length - usage) / 8 ))s"

		blocks=( "" "▏" "▎" "▍" "▌" "▋" "▊" "▉" )
		printf "\e[K%-*s %s [${3}${prog// /█}${blocks[usage % 8]}${3:+${NC}}${total}]\r" "$length" "${2}" "${label}"
	fi
}

# Calculate mean/average, standard deviation, median, min and max
# calc <times>...
calc() {
	# printf '%s\n' "$@" | awk 'NR==1 { max=min=$1 } { if ($1>max) max=$1; if ($1<min) min=$1; sum+=$1; sumsq+=$1^2 } END { printf "%.15g\t%.15g\t%.15g\t%.15g\n", sum/NR, sqrt(sumsq/NR-(sum/NR)^2), min, max }'
	printf '%s\n' "$@" | sort -n | awk '{ arr[NR]=$1; sum+=$1; sumsq+=$1^2 } END { mean=sum/NR; variance=sumsq/NR-mean^2; printf "%.15g\t%.15g\t%.15g\t%.15g\t%.15g\n", mean, sqrt(variance<0 ? 0 : variance), (NR%2==1) ? arr[(NR+1)/2] : (arr[NR/2]+arr[NR/2+1])/2, arr[1], arr[NR] }'
}

# Calculate mean/average
# mean <times>...
mean() {
	printf '%s\n' "$@" | awk '{ sum+=$1 } END { printf "%.15g\n", sum/NR }'
}

# Calculate speed, standard deviation and percentage
# ratio_stddev <mean> <standard deviation> <fastest mean> <fastest standard deviation>
ratio_stddev() {
	echo "$1 $2 $3 $4" | awk '{ mean=$1/$3; printf "%.15g\t%.15g\t%.15g\n", mean, mean * sqrt(($2/$1)^2+($4/$3)^2), mean * 100 }'
}

# Calculate median
# median <times>...
median() {
	printf '%s\n' "$@" | sort -n | awk '{ arr[NR]=$1 } END { printf "%.15g\n", (NR%2==1) ? arr[(NR+1)/2] : (arr[NR/2]+arr[NR/2+1])/2 }'
}

# Calculate modified Z-scores
# Adapted from: https://github.com/sharkdp/hyperfine/blob/master/src/hyperfine/outlier_detection.rs
# modified_zscores <times>...
modified_zscores() {
	local x_median deviations mad 
	
	x_median=$(median "$@")
	deviations=( $(printf '%s\n' "$@" | awk 'function abs(x) { return x<0 ? -x : x } { printf "%.15g\n", abs($1 - '"$x_median"') }') )
	mad=$(median "${deviations[@]}")
	printf '%s\n' "$@" | awk 'function abs(x) { return x<0 ? -x : x } BEGIN { mad='"$mad"'; if(mad==0) mad=10^-308 } { printf "%.15g\n", abs(($1 - '"$x_median"') / mad) }'
}

# Run preparation command
# prepare <commands index>
prepare() {
	if [[ ${#PREPARE[*]} -gt 0 ]]; then
		output=$(eval "${PREPARE[${#PREPARE[*]} > 1 ? $1 : 0]}" >/dev/null 2>&1)
		E=$?
		if (( E )); then
			if [[ -n "$INTERACTIVE" ]]; then
				echo -e -n '\e[K'
			fi
			error "The preparation command terminated with a non-zero exit code: $E. Append ' || true' to the command if you are sure that this can be ignored. Output: $output"
		fi
	fi
}

# Run command
# run <commands index>
run() {
	local array
	
	prepare "$i"
	
	output=$(TIMEFORMAT='%R %U %S'; { time eval "${COMMANDS[$1]}" >/dev/null 2>&1; } 2>&1)
	E=$?
	if (( E )); then
		if [[ -z "$FAILURE" ]]; then
			if [[ -n "$INTERACTIVE" ]]; then
				echo -e -n '\e[K'
			fi
			error "Command terminated with non-zero exit code: $E. Use the '-i' ignore-failure option if you want to ignore this. Output: $(echo "$output" | head -n -1)"
		fi
		((++ERRORS))
	fi
	
	array=( $output )
	ELAPSED+=( "${array[0]}" )
	USER+=( "${array[1]}" )
	SYSTEM+=( "${array[2]}" )
}

RE='^[0-9]+$'
if ! [[ $WARMUP =~ $RE ]]; then
	echo "Usage: Warmup must be a number" >&2
	exit 1
fi

if [[ ${#PREPARE[*]} -gt 1 && ${#COMMANDS[*]} -ne ${#PREPARE[*]} ]]; then
	echo "Error: The prepare option has to be provided just once or N times, where N is the number of benchmark commands." >&2
	exit 1
fi

if [[ -n "$MINRUNS" && ! $MINRUNS =~ $RE ]]; then
	echo "Usage: The minimum number of runs must be a number" >&2
	exit 1
fi
if [[ -n "$MAXRUNS" && ! $MAXRUNS =~ $RE ]]; then
	echo "Usage: The maximum number of runs must be a number" >&2
	exit 1
fi

if [[ -n "$RUNS" ]]; then
	if ! [[ $RUNS =~ $RE ]]; then
		echo "Usage: The number of runs must be a number" >&2
		exit 1
	fi
	
	MINRUNS=$RUNS
	MAXRUNS=$RUNS
fi

if [[ -n "$MINRUNS" && $MINRUNS -lt 2 ]] || [[ -n "$MAXRUNS" && $MAXRUNS -lt 2 ]]; then
	echo "Error: Number of runs below two." >&2
	exit 1
fi

if [[ -n "$MAXRUNS" ]]; then
	if [[ -z "$MINRUNS" && $MAXRUNS -lt $MIN ]]; then
		MINRUNS=$MAXRUNS
	fi
		
	if [[ -n "$MINRUNS" && $MINRUNS -gt $MAXRUNS ]]; then
		echo "Error: The minimum number of runs must be greater then or equal to the maximum number of runs." >&2
		exit 1
	fi
fi

MINRUNS=${MINRUNS:-$MIN}

if [[ -n "$CSV" && -e "$CSV" ]]; then
	echo "Error: File \"$CSV\" already exists." >&2
	exit 1
fi
if [[ -n "$JSON" && -e "$JSON" ]]; then
	echo "Error: File \"$JSON\" already exists." >&2
	exit 1
fi

if [[ -n "$CSV" ]]; then
	# echo 'command,mean,stddev,median,user,system,min,max' > "$CSV"
	echo 'Command,Mean (s),Std Dev (s),Median (s),Mean User (s),Mean System (s),Min (s),Max (s)' > "$CSV"
fi
if [[ -n "$JSON" ]]; then
	echo -n '{
  "results": [' > "$JSON"
fi

MEAN=()
STDDIV=()

for i in "${!COMMANDS[@]}"; do
	# Elapsed (wall clock) times
	ELAPSED=()
	# User times
	USER=()
	# System times
	SYSTEM=()
	
	ERRORS=0
	
	RUNS=$MINRUNS
	
	printf "${BOLD}Benchmark #%'d${NC}: %s\n" "$((i+1))" "${COMMANDS[i]}"
	
	if [[ $WARMUP -gt 0 ]]; then
		if [[ -n "$INTERACTIVE" ]]; then
			bar 0 "Performing warmup runs"
			
			percentages=( $(for (( j = 0; j <= WARMUP; ++j )); do echo "$j"; done | awk '{ printf "%.15g\n", $1 / '"$WARMUP"' * 100 }') )
		fi
	
		for ((j = 0; j < WARMUP; ++j)); do
			prepare "$i"
			
			output=$(eval "${COMMANDS[i]}" >/dev/null 2>&1)
			E=$?
			if (( E )) && [[ -z "$FAILURE" ]]; then
				if [[ -n "$INTERACTIVE" ]]; then
					echo -e -n '\e[K'
				fi
				error "Command terminated with non-zero exit code: $E. Use the '-i' ignore-failure option if you want to ignore this. Output: $output"
			fi
			
			((k=j+1))
			if [[ -n "$INTERACTIVE" ]] && [[ $WARMUP -le 20 || $(( k % (WARMUP / MIN) )) -eq 0 || $k -eq $WARMUP ]]; then
				bar "${percentages[k]}" "$(printf "Performing warmup run %'d/%'d" "$k" "$WARMUP")"
			fi
		done
	fi
	
	if [[ -n "$INTERACTIVE" ]]; then
		bar 0 "Initial time measurement"
	fi
	
	run "$i"
	
	runs=$(echo "$MINTIME ${ELAPSED[0]}" | awk '{ printf "%d", $1 / $2 }')
	
	if [[ $runs -gt $MINRUNS ]]; then
		if [[ -n "$MAXRUNS" && $runs -gt $MAXRUNS ]]; then
			RUNS=$MAXRUNS
		else
			RUNS=$runs
		fi
	fi
	
	if [[ -n "$INTERACTIVE" ]]; then
		percentages=( $(for (( j = 0; j <= RUNS; ++j )); do echo "$j"; done | awk '{ printf "%.15g\n", $1 / '"$RUNS"' * 100 }') )
		bar "${percentages[1]}" "$(printf "Run %'d/%'d, estimate: ${GREEN}%.3fs${NC}" 1 "$RUNS" "${ELAPSED[0]/./$decimal_point}")"
	fi
	
	for ((j = 1; j < RUNS; ++j)); do
		run "$i"
		
		((k=j+1))
		if [[ -n "$INTERACTIVE" ]] && [[ $RUNS -le 20 || $(( k % (RUNS / MIN) )) -eq 0 || $k -eq $RUNS ]]; then
			amean=$(mean "${ELAPSED[@]}")
			bar "${percentages[k]}" "$(printf "Run %'d/%'d, estimate: ${GREEN}%.3fs${NC}" "$k" "$RUNS" "${amean/./$decimal_point}")"
		fi
		# echo "${ELAPSED[j]}"
	done
	
	if [[ -n "$INTERACTIVE" ]]; then
		echo -e -n '\e[K'
	fi
	
	if [[ -n "$CLEANUP" ]]; then
		output=$(eval "$CLEANUP" >/dev/null 2>&1)
		E=$?
		if (( E )); then
			error "The cleanup command terminated with a non-zero exit code: $E. Append ' || true' to the command if you are sure that this can be ignored. Output: $output"
		fi
	fi

	array=( $(calc "${ELAPSED[@]}") )
	amean=${array[0]}
	MEAN+=( "$amean" )
	stddiv=${array[1]}
	STDDIV+=( "$stddiv" )
	amedian=${array[2]}
	min=${array[3]}
	max=${array[4]}

	usermean=$(mean "${USER[@]}")
	systemmean=$(mean "${SYSTEM[@]}")
	
	# CPU used
	cpu=$(echo "$amean $usermean $systemmean" | awk '{ printf "%.15g\n", ($2 + $3) / $1 * 100 }')
	
	if [[ -z "$UNICODE" ]]; then
		printf "  Time (${GREEN}${BOLD}mean${NC} +- ${GREEN}${DIM}std dev${NC}):          ${GREEN}${BOLD}%7.4fs${NC} +- ${GREEN}${DIM}%7.4fs${NC}             [User: ${BLUE}%.4fs${NC}, System: ${BLUE}%.4fs${NC}]\n" "${amean/./$decimal_point}" "${stddiv/./$decimal_point}" "${usermean/./$decimal_point}" "${systemmean/./$decimal_point}"
		printf "  Range (${CYAN}min${NC} ... ${GREEN}median${NC} ... ${MAGENTA}max${NC}):  ${CYAN}%6.3fs${NC} ... ${GREEN}%6.3fs${NC} ... ${MAGENTA}%6.3fs${NC}   CPU: %5.1f%%, ${DIM}%'d runs${NC}\n" "${min/./$decimal_point}" "${amedian/./$decimal_point}" "${max/./$decimal_point}" "${cpu/./$decimal_point}" "$RUNS"
	else
		printf "  Time (${GREEN}${BOLD}x̅ mean${NC} ± ${GREEN}${DIM}σ std dev${NC}):     ${GREEN}${BOLD}%7.4fs${NC} ± ${GREEN}${DIM}%7.4fs${NC}          [User: ${BLUE}%.4fs${NC}, System: ${BLUE}%.4fs${NC}]\n" "${amean/./$decimal_point}" "${stddiv/./$decimal_point}" "${usermean/./$decimal_point}" "${systemmean/./$decimal_point}"
		printf "  Range (${CYAN}min${NC} … ${GREEN}x̃ median${NC} … ${MAGENTA}max${NC}):  ${CYAN}%6.3fs${NC} … ${GREEN}%6.3fs${NC} … ${MAGENTA}%6.3fs${NC}   CPU: %5.1f%%, ${DIM}%'d runs${NC}\n" "${min/./$decimal_point}" "${amedian/./$decimal_point}" "${max/./$decimal_point}" "${cpu/./$decimal_point}" "$RUNS"
	fi

	if [[ -n "$CSV" ]]; then
		printf '%s,%s,%s,%s,%s,%s,%s,%s\n' "${COMMANDS[i]}" "$amean" "$stddiv" "$amedian" "$usermean" "$systemmean" "$min" "$max" >> "$CSV"
	fi
	if [[ -n "$JSON" ]]; then
		{
			if [[ $i -gt 0 ]]; then
				printf ','
			fi
			printf '
    {
      "command": "%s",
      "mean": %s,
      "stddev": %s,
      "median": %s,
      "user": %s,
      "system": %s,
      "min": %s,
      "max": %s,
      "times": [\n' "${COMMANDS[i]}" "$amean" "$stddiv" "$amedian" "$usermean" "$systemmean" "$min" "$max"
			printf '        %s,\n' "${ELAPSED[@]::${#ELAPSED[*]}-1}"
			printf '        %s
      ]
    }' "${ELAPSED[@]: -1}"
		} >> "$JSON"
	fi
	
	echo
  
	if (( output=$(printf '%s\n' "${ELAPSED[@]}" | awk '$1<'"$MINEXECUTIONTIME"' { ++t } END { printf "%d", t }') )); then
		warning "$output run(s) of this command took less than $MINEXECUTIONTIME seconds to complete. Results might be inaccurate."
	fi
	
	if [[ $ERRORS -gt 0 ]]; then
		warning "Ignoring $ERRORS non-zero exit code(s)."
	fi
	
	scores=( $(modified_zscores "${ELAPSED[@]}") )
	if (( $(echo "${scores[0]} $OUTLIERTHRESHOLD" | awk '{ print ($1>$2) }') )); then
		warning "The first benchmarking run for this command was significantly slower than the rest (${ELAPSED[0]}s). This could be caused by (filesystem) caches that were not filled until after the first run. You should consider using the warmup option to fill those caches before the actual benchmark. Alternatively, use the prepare option to clear the caches before each timing run."
	elif (( output=$(printf '%s\n' "${scores[@]}" | awk '$1>'"$OUTLIERTHRESHOLD"' { ++t } END { printf "%d", t }') )); then
		warning "$output statistical outlier(s) were detected (> $OUTLIERTHRESHOLD modified Z-scores or about 10${UNICODE:+σ} std devs). Consider re-running this benchmark on a quiet system without any interferences from other programs. It might help to use the warmup or prepare options."
	fi
	# printf '%s\n' "${scores[@]}"
done

if [[ -n "$JSON" ]]; then
	echo '
  ]
}' >> "$JSON"
fi

if [[ ${#MEAN[*]} -gt 1 ]]; then
	MIN=${MEAN[0]}
	fastest=0
	for i in "${!MEAN[@]}"; do
		if (( $(echo "${MEAN[i]} $MIN" | awk '{ print ($1<$2) }') )); then
			MIN=${MEAN[i]}
			fastest=$i
		fi
	done
	
	echo -e "${BOLD}Summary${NC}"
	if [[ -z "$UNICODE" ]]; then
		printf "  #%'d '${CYAN}%s${NC}' ran\n" "$((fastest+1))" "${COMMANDS[fastest]}"
	else
		printf "  #%'d ‘${CYAN}%s${NC}’ ran\n" "$((fastest+1))" "${COMMANDS[fastest]}"
	fi
	
	for i in "${!MEAN[@]}"; do
		if [[ $i -ne $fastest ]]; then
			array=( $(ratio_stddev "${MEAN[i]}" "${STDDIV[i]}" "${MEAN[fastest]}" "${STDDIV[fastest]}") )
			
			if [[ -z "$UNICODE" ]]; then
				printf "${GREEN}${BOLD}%9.3f${NC} +- ${GREEN}%.3f${NC} times (%'.1f%%) faster than #%'d '${MAGENTA}%s${NC}'\n" "${array[0]/./$decimal_point}" "${array[1]/./$decimal_point}" "${array[2]/./$decimal_point}" "$((i+1))" "${COMMANDS[i]}"
			else
				printf "${GREEN}${BOLD}%9.3f${NC} ± ${GREEN}%.3f${NC} times (%'.1f%%) faster than #%'d ‘${MAGENTA}%s${NC}’\n" "${array[0]/./$decimal_point}" "${array[1]/./$decimal_point}" "${array[2]/./$decimal_point}" "$((i+1))" "${COMMANDS[i]}"
			fi
		fi
	done
fi
