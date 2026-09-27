# SafeShield statistics: aggregation, log parsing, and serialization helpers.
# Loaded together with the other statistics/*.awk modules by safeshield-statsd.

function recompute_totals(    bucket, composite, parts, key, stale_count, i) {
	total_queries = 0
	total_blocked = 0
	for (bucket in queries) {
		total_queries += queries[bucket] + 0
		total_blocked += blocked[bucket] + 0
	}

	for (key in device_seen) {
		device_queries[key] = 0
		device_blocked[key] = 0
		delete device_first_bucket[key]
		delete device_last_bucket[key]
	}
	for (composite in device_hour_queries) {
		split(composite, parts, SUBSEP)
		key = parts[1]
		bucket = parts[2] + 0
		device_queries[key] += device_hour_queries[composite] + 0
		device_blocked[key] += device_hour_blocked[composite] + 0
		if (!(key in device_first_bucket) || bucket < (device_first_bucket[key] + 0)) {
			device_first_bucket[key] = bucket
		}
		if (!(key in device_last_bucket) || bucket > (device_last_bucket[key] + 0)) {
			device_last_bucket[key] = bucket
		}
	}

	stale_count = 0
	for (key in device_seen) {
		if ((device_queries[key] + 0) == 0 && (device_blocked[key] + 0) == 0) {
			stale_devices[++stale_count] = key
		}
	}
	for (i = 1; i <= stale_count; i++) {
		remove_device(stale_devices[i])
		delete stale_devices[i]
	}
}

function extract_query_client(line,    client) {
	client = line
	if (client !~ / from /) {
		return ""
	}
	sub(/^.* from /, "", client)
	sub(/[[:space:]].*$/, "", client)
	return client
}

function extract_extra_client(line,    payload, fields, count, client) {
	payload = line
	sub(/^.*dnsmasq\[[0-9]+\]:[[:space:]]*/, "", payload)
	count = split(payload, fields, /[[:space:]]+/)
	if (count < 3 || fields[1] !~ /^[0-9]+$/) {
		return ""
	}

	client = fields[2]
	sub(/\/[0-9]+$/, "", client)
	return client
}

function shell_quote(value,    quoted) {
	quoted = value
	gsub(/'/, "'\\''", quoted)
	return "'" quoted "'"
}

function json_escape(value,    escaped) {
	escaped = value
	gsub(/\\/, "\\\\", escaped)
	gsub(/"/, "\\\"", escaped)
	gsub(/\r/, "\\r", escaped)
	gsub(/\n/, "\\n", escaped)
	gsub(/\t/, "\\t", escaped)
	return escaped
}

function replace_file(tmp, final,    rc) {
	rc = system("mv -f " shell_quote(tmp) " " shell_quote(final))
	return rc == 0
}
