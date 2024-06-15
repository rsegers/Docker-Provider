#!/bin/bash

# Get the directory where the script is located
script_dir=$(dirname "$0")

mdsd_log_file="$script_dir/mdsd.info"
ci_log_file="$script_dir/fluent-bit-out-oms-runtime.log"

echo "mdsd log file: ${mdsd_log_file}"
echo "ci log file: ${ci_log_file}"

totalLogRecordCountFromCILogFile() {
    # Check if the log file exists
    if [ ! -f "$1" ]; then
        echo "Log file not found: $1"
        exit 1
    fi

    # Create a temporary file to store the filtered log lines
    temp_file=$(mktemp)

    # Filter the log lines and write to the temporary file
    cat $1 | grep "container log records" > $temp_file
    mv "$temp_file" "$1"

    # Initialize counter
    total_records=0

    # Read the log file line by line
    while IFS= read -r line; do
        # Extract the number of container log records from each line
        records=$(echo "$line" | awk -F'container log records' '{print $1}' | awk '{print $NF}')
        # Increment the total count
        ((total_records += records))
    done < "$1"

    echo "$total_records"
}

totalLogRecordCountByMDSDMsgPackReceived() {
    # Check if the log file exists
    if [ ! -f "$1" ]; then
        echo "Log file not found: $1"
        exit 1
    fi

    # Create a temporary file to store the filtered log lines
    temp_file=$(mktemp)
    cat $1 | grep "MessagePack received records:" > $temp_file
    mv "$temp_file" "$1"


    # Initialize counter
    total_records=0

    # Read the log file line by line
    while IFS= read -r line; do
        # Extract the number of container log records from each line
        records=$(echo "$line"  | grep -oE 'records: [0-9]+' | sed 's/records: //')
        # Increment the total count
        ((total_records += records))
    done < "$1"

    echo "$total_records"
}

totalLogRecordCountByMDSDMsgPackReceived() {
    # Check if the log file exists
    if [ ! -f "$1" ]; then
        echo "Log file not found: $1"
        exit 1
    fi

    # Create a temporary file to store the filtered log lines
    temp_file=$(mktemp)
    cat $1 | grep "MessagePack decoded records:" > $temp_file
    mv "$temp_file" "$1"


    # Initialize counter
    total_records=0

    # Read the log file line by line
    while IFS= read -r line; do
        # Extract the number of container log records from each line
        records=$(echo "$line"  | grep -oE 'records: [0-9]+' | sed 's/records: //')
        # Increment the total count
        ((total_records += records))
    done < "$1"

    echo "$total_records"
}

total_records=$(totalLogRecordCountFromCILogFile "$ci_log_file")
echo "Total container log records ingested by CI : $total_records"

total_records=$(totalLogRecordCountByMDSDMsgPackReceived "$mdsd_log_file")
echo "Total Msgpack received container log records by MDSD: $total_records"

total_records=$(totalLogRecordCountByMDSDMsgPackReceived "$mdsd_log_file")
echo "Total Msgpack decoded container log records by MDSD: $total_records"
