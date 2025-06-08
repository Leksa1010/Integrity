# Display usage
usage() {
	echo "Usage: $0 -d <directory> | -f <file> | -c <check> -o <output_file>"
	echo " -d <directory>	Initialize or check hashes of files in a directory"
	echo " -f <file>	Initialize or check hash of a single file"
	echo " -c <check>	Check if files have been modified based on hashes"
	echo " -o <output_file>	Output file to store hashes (default: .file_hashes.json)"
	exit 1
}

# Get the timestamp, size, and sha256sum of each file
get_info() {
	local file="$1"
	# Get raw timestamp from stat
	raw_timestamp=$(stat --format="%y" "$file")
    
	# Convert the raw timestamp into a more readable format using date
	timestamp=$(date -d "$raw_timestamp" "+%Y-%m-%d %H:%M:%S")
    
	# Get file size and calculate hash
	size=$(stat --format="%s" "$file")
	hash=$(sha256sum "$file" | awk '{print $1}')
}

# Create JSON object for our needs
make_json() {
	local file="$1"
	local timestamp="$2"
	local size="$3"
	local hash="$4"

	json_record=$(cat <<EOF
{
	"filename": "$file",
	"timestamp": "$timestamp",
	"size": "$size",
	"sha256": "$hash"
}
EOF
)
}


# Initialize hashes for a directory
hash_dir() {
	local dir="$1"
	local output="$2"
    
	# Check if directory exists
	if [ ! -d "$dir" ]; then
		echo "Error: Directory '$dir' does not exist!"
		exit 1
	fi
    
	# Start JSON array
	echo "[" > "$output"
	first=1

	# Loop through files in the directory and get needed info about files
	find "$dir" -type f | while read -r file; do
		# Get file info (timestamp, size, hash)
		get_info "$file"
        
		# Prepare the JSON object for the current file
		make_json "$file" "$timestamp" "$size" "$hash"
        
		# Append the JSON record to the output file (add comma if not the first record)
		if [ $first -eq 0 ]; then
			echo "," >> "$output"
		fi
        
		echo "$json_record" >> "$output"
			first=0
	done
    
	# Close the JSON array
	echo "]" >> "$output"
}

# Initialize hash for a single file
hash_file() {
	local file="$1"
	local output="$2"
    
	# Check if file exists
	if [ ! -f "$file" ]; then
		echo "Error: File '$file' does not exist!"
		exit 1
	fi
    
	# Get file info (timestamp, size, hash)
	get_info "$file"
    
	# Create the JSON object for the file
	make_json "$file" "$timestamp" "$size" "$hash"

    
	# Create and append to the JSON file
	echo "[" > "$output"
	echo "$json_record" >> "$output"
	echo "]" >> "$output"
}

# Check for modifications in files
check_modifications() {
	local input="$1"
    
	# Check if the hash file exists
	if [ ! -f "$input" ]; then
		echo "Error: Hash file '$input' does not exist!"
		exit 1
	fi
    
	# Read the hash file into an array of JSON objects
	existing_hashes=$(cat "$input")
    
	# Loop through all files in the hash file and check for modifications
	echo "$existing_hashes" | jq -c '.[]' | while read -r json_record; do
		# Get the filename from the record
		filename=$(echo "$json_record" | jq -r '.filename')
        
		# Check if the file exists
		if [ ! -f "$filename" ]; then
			echo "File '$filename' no longer exists!"
			continue
		fi
        
		# Get the current metadata of the file
		file=$filename
		get_info "$file"
        
		# Compare the current file metadata with the stored metadata
		stored_timestamp=$(echo "$json_record" | jq -r '.timestamp')
		stored_size=$(echo "$json_record" | jq -r '.size')
		stored_hash=$(echo "$json_record" | jq -r '.sha256')
        
		# Compare each property
		if [ "$stored_timestamp" != "$timestamp" ]; then
			echo "Timestamp modified: $filename"
		fi
	        
		if [ "$stored_size" != "$size" ]; then
			echo "Size modified: $filename"
		fi
        
		if [ "$stored_hash" != "$hash" ]; then
			echo "Hash modified: $filename"
		fi
	done
}

# Default hidden hash file name prefix
output_prefix=".file_hashes"

dir=""
file=""
check=""
input_file=""

# Parse command line arguments
while getopts "d:f:c::o:h" opt; do
	case "$opt" in
	d) # Initialize directory hashes
		dir=$OPTARG ;;
	f) # Initialize single file hash
		file=$OPTARG ;;
	c) # Check for modifications, optional input file
    
		check=true
		if [ -n "$OPTARG" ]; then
			input_file="$OPTARG"
		fi ;;
	o) # Specify the output file name prefix
		output_prefix=$OPTARG ;;
	h) # Display help
		usage ;;
	*) # Invalid option
		usage ;;
	esac
done

# Ensure that either -d, -f, or -c is provided
if [ -z "$dir" ] && [ -z "$file" ] && [ -z "$check" ]; then
	usage
fi


# Construct the output/input filename
if [ -z "$input_file" ]; then
	output_file=".${output_prefix}.json"
else
	output_file="$input_file"
fi


# Check which function to run based on what option is chosen
if [ ! -z "$dir" ]; then
	hash_dir "$dir" "$output_file"
elif [ ! -z "$file" ]; then
	hash_file "$file" "$output_file"
elif [ ! -z "$check" ]; then
	check_modifications "$output_file"
fi
