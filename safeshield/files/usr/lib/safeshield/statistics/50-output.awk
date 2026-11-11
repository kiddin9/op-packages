# SafeShield statistics: JSON snapshots and persistence scheduling.
# Loaded together with the other statistics/*.awk modules by safeshield-statsd.

function statistics_first_hour(now,    current_hour, cutoff, first_hour) {
	current_hour = hour_start(now)
	cutoff = current_hour - ((retention_hours - 1) * 3600)
	first_hour = hour_start(started_at)
	if (first_hour < cutoff) {
		first_hour = cutoff
	}
	return first_hour
}

function is_unknown_output_device(key) {
	return (key == "unknown" || key == "other" || (device_mac[key] == "" && key ~ /^ip:/))
}

# Never let one stale/corrupt per-client hour block a whole cloud reconciliation.
# This is a projection only: raw hourly counters and flash state are untouched.
# Suppress all client attribution for an inconsistent hour rather than guessing
# which client was wrong or inventing replacement counts. Router totals survive.
function prepare_safe_hourly(first_hour, last_hour,    bucket, composite, parts, key, client_queries, client_blocked) {
	sanitized_hour_count = 0
	for (bucket = first_hour; bucket <= last_hour; bucket += 3600) {
		delete masked_hour[bucket]
		attributed_hour_queries[bucket] = 0
		attributed_hour_blocked[bucket] = 0
		safe_hour_blocked[bucket] = blocked[bucket] + 0
		if (safe_hour_blocked[bucket] > queries[bucket] + 0) {
			safe_hour_blocked[bucket] = queries[bucket] + 0
			masked_hour[bucket] = 1
		}
	}

	for (composite in device_hour_queries) {
		split(composite, parts, SUBSEP)
		key = parts[1]
		bucket = parts[2] + 0
		if (!(key in device_seen) || bucket < first_hour || bucket > last_hour) {
			continue
		}
		client_queries = device_hour_queries[composite] + 0
		client_blocked = device_hour_blocked[composite] + 0
		attributed_hour_queries[bucket] += client_queries
		attributed_hour_blocked[bucket] += client_blocked
		if (client_blocked > client_queries) {
			masked_hour[bucket] = 1
		}
	}

	for (bucket = first_hour; bucket <= last_hour; bucket += 3600) {
		if (attributed_hour_queries[bucket] > queries[bucket] + 0 || \
			attributed_hour_blocked[bucket] > safe_hour_blocked[bucket]) {
			masked_hour[bucket] = 1
		}
		if (masked_hour[bucket]) {
			sanitized_hour_count++
		}
	}
}

function clear_safe_hourly(first_hour, last_hour,    bucket) {
	for (bucket = first_hour; bucket <= last_hour; bucket += 3600) {
		delete masked_hour[bucket]
		delete attributed_hour_queries[bucket]
		delete attributed_hour_blocked[bucket]
		delete safe_hour_blocked[bucket]
	}
}

function save_json_range(path, now, first_hour, last_hour, include_empty_devices,    tmp, bucket, comma, key, identified, device_comma, identity_comma, composite, device_first_hour, device_last_hour, persistence_enabled, persistent, healthy, volatile_state, storage, persistence_mode, truncated, range_queries, range_blocked, device_range_queries, device_range_blocked, device_has_rows, unknown_has_rows, unknown_queries, unknown_blocked) {
	if (path == "") {
		return 1
	}

	tmp = path ".tmp"
	if (first_hour > last_hour) {
		first_hour = last_hour
	}

	persistence_enabled = (persistent_state_file != "" || persistent_journal_file != "") ? "true" : "false"
	persistent = (persistence_enabled == "true" && persistence_healthy && persistent_updated_at > 0) ? "true" : "false"
	healthy = (persistence_enabled == "true") ? (persistence_healthy ? "true" : "false") : "true"
	volatile_state = (persistence_enabled == "true") ? "false" : "true"
	storage = (persistence_enabled == "true") ? "tmpfs+flash" : "tmpfs"
	persistence_mode = (persistent_journal_file != "") ? "journal" : ((persistent_state_file != "") ? "snapshot" : "none")
	truncated = devices_truncated ? "true" : "false"
	# Keep malformed source metadata from invalidating an otherwise sound upload.
	safe_untracked_blocked = source_untracked_blocked
	if (safe_untracked_blocked > source_untracked_queries) {
		safe_untracked_blocked = source_untracked_queries
	}
	prepare_safe_hourly(first_hour, last_hour)

	range_queries = 0
	range_blocked = 0
	for (bucket = first_hour; bucket <= last_hour; bucket += 3600) {
		range_queries += queries[bucket] + 0
		range_blocked += safe_hour_blocked[bucket]
		delete unknown_hour_queries[bucket]
		delete unknown_hour_blocked[bucket]
	}

	# IP-only identities are intentionally retained internally for a short period
	# so a later DHCP/ARP/NDP observation can migrate their history to a real
	# device. They are serialized as one logical "unknown" client so temporary
	# IPv6 privacy addresses cannot create unbounded client records in the Hub/UI.
	unknown_has_rows = 0
	unknown_queries = 0
	unknown_blocked = 0
	for (key in device_seen) {
		if (!is_unknown_output_device(key)) {
			continue
		}
		# An upload contains only a short recent window. Ignore provisional
		# devices whose retained buckets fall completely outside that window.
		if ((device_last_bucket[key] + 0) < first_hour ||
			(device_first_bucket[key] + 0) > last_hour) {
			continue
		}
		for (bucket = first_hour; bucket <= last_hour; bucket += 3600) {
			if (masked_hour[bucket]) {
				continue
			}
			composite = device_bucket_key(key, bucket)
			if (!((composite in device_hour_queries) || (composite in device_hour_blocked))) {
				continue
			}
			unknown_has_rows = 1
			unknown_hour_queries[bucket] += device_hour_queries[composite] + 0
			unknown_hour_blocked[bucket] += device_hour_blocked[composite] + 0
			unknown_queries += device_hour_queries[composite] + 0
			unknown_blocked += device_hour_blocked[composite] + 0
		}
	}

	printf "{\"schema\":{\"name\":\"safeshield.statistics\",\"version\":3}," > tmp
	printf "\"volatile\":%s,\"storage\":\"%s\",\"persistent\":%s,", volatile_state, storage, persistent >> tmp
	printf "\"persistence_enabled\":%s,\"persistence_healthy\":%s,", persistence_enabled, healthy >> tmp
	printf "\"persistence_mode\":\"%s\",", persistence_mode >> tmp
	printf "\"persistent_error_count\":%d,\"persistent_last_error_at\":%d,", persistent_error_count, persistent_last_error_at >> tmp
	printf "\"persistent_updated_at\":%d,\"persistent_checkpoint_interval_s\":%d,", persistent_updated_at, persistent_interval >> tmp
	printf "\"persistent_compacted_at\":%d,\"persistent_compact_interval_s\":%d,", persistent_compacted_at, persistent_compact_interval >> tmp
	printf "\"snapshot_interval_s\":%d,", snapshot_interval >> tmp
	printf "\"generation_id\":\"%s\",", json_escape(generation_id) >> tmp
	printf "\"snapshot_seq\":%d,", snapshot_seq >> tmp
	printf "\"source\":{\"backend\":\"dnsmasq_ubus\",\"available\":%s,", source_available ? "true" : "false" >> tmp
	printf "\"instance_id\":\"%s\",\"transport_scope\":\"%s\",", \
		json_escape(source_instance_id), json_escape(source_transport_scope) >> tmp
	printf "\"client_capacity\":%d,\"tracked_clients\":%d,\"untracked_queries\":%d,", \
		source_client_capacity, source_tracked_clients, source_untracked_queries >> tmp
	printf "\"untracked_blocked\":%d,", safe_untracked_blocked >> tmp
	printf "\"poll_error_count\":%d,\"last_error_at\":%d,\"sanitized_hours\":%d},", \
		source_error_count, source_last_error_at, sanitized_hour_count >> tmp
	printf "\"started_at\":%d,\"session_started_at\":%d,\"updated_at\":%d,", started_at, session_started_at, now >> tmp
	printf "\"retention_hours\":%d,", retention_hours >> tmp
	printf "\"device_limit\":%d,\"devices_truncated\":%s,", max_devices, truncated >> tmp
	printf "\"totals\":{\"queries\":%d,\"blocked\":%d},", range_queries, range_blocked >> tmp
	printf "\"hourly\":[" >> tmp

	comma = ""
	for (bucket = first_hour; bucket <= last_hour; bucket += 3600) {
		printf "%s{\"bucket_start\":%d,\"queries\":%d,\"blocked\":%d}", comma, bucket, queries[bucket] + 0, safe_hour_blocked[bucket] >> tmp
		comma = ","
	}
	printf "],\"devices\":[" >> tmp

	comma = ""
	for (key in device_seen) {
		if (is_unknown_output_device(key)) {
			continue
		}
		device_first_hour = device_first_bucket[key] + 0
		device_last_hour = device_last_bucket[key] + 0
		if (device_first_hour <= 0 || device_first_hour < first_hour) {
			device_first_hour = first_hour
		}
		if (device_last_hour <= 0 || device_last_hour > last_hour) {
			device_last_hour = last_hour
		}

		device_range_queries = 0
		device_range_blocked = 0
		device_has_rows = 0
		if (device_first_hour <= device_last_hour) {
			for (bucket = device_first_hour; bucket <= device_last_hour; bucket += 3600) {
				if (masked_hour[bucket]) {
					continue
				}
				composite = device_bucket_key(key, bucket)
				if (!((composite in device_hour_queries) || (composite in device_hour_blocked))) {
					continue
				}
				device_has_rows = 1
				device_range_queries += device_hour_queries[composite] + 0
				device_range_blocked += device_hour_blocked[composite] + 0
			}
		}
		if (!include_empty_devices && !device_has_rows) {
			continue
		}

		identified = (device_mac[key] != "") ? "true" : "false"
		printf "%s{\"id\":\"%s\",\"mac\":\"%s\",\"ip\":\"%s\",\"hostname\":\"%s\",\"identified\":%s,\"queries\":%d,\"blocked\":%d,\"identities\":[", \
			comma, \
			json_escape(key), \
			json_escape(device_mac[key]), \
			json_escape(device_ip[key]), \
			json_escape(device_hostname[key]), \
			identified, \
			device_range_queries, \
			device_range_blocked >> tmp

		identity_comma = ""
		if (device_duid[key] != "") {
			printf "%s{\"type\":\"dhcpv6_duid\",\"value\":\"%s\"}", \
				identity_comma, json_escape(device_duid[key]) >> tmp
			identity_comma = ","
		}
		if (device_client_id[key] != "") {
			printf "%s{\"type\":\"dhcp_client_id\",\"value\":\"%s\"}", \
				identity_comma, json_escape(device_client_id[key]) >> tmp
			identity_comma = ","
		}
		if (device_mac[key] != "") {
			printf "%s{\"type\":\"mac\",\"value\":\"%s\"}", \
				identity_comma, json_escape(device_mac[key]) >> tmp
		}
		printf "],\"hourly\":[" >> tmp

		device_comma = ""
		if (device_first_hour <= device_last_hour) {
			for (bucket = device_first_hour; bucket <= device_last_hour; bucket += 3600) {
				if (masked_hour[bucket]) {
					continue
				}
				composite = device_bucket_key(key, bucket)
				if (!((composite in device_hour_queries) || (composite in device_hour_blocked))) {
					continue
				}
				printf "%s{\"bucket_start\":%d,\"queries\":%d,\"blocked\":%d}", \
					device_comma, bucket, device_hour_queries[composite] + 0, device_hour_blocked[composite] + 0 >> tmp
				device_comma = ","
			}
		}
		printf "]}" >> tmp
		comma = ","
	}

	if (unknown_has_rows) {
		printf "%s{\"id\":\"unknown\",\"mac\":\"\",\"ip\":\"\",\"hostname\":\"Unknown devices\",\"identified\":false,\"queries\":%d,\"blocked\":%d,\"hourly\":[", \
			comma, unknown_queries, unknown_blocked >> tmp
		device_comma = ""
		for (bucket = first_hour; bucket <= last_hour; bucket += 3600) {
			if (masked_hour[bucket] || !((bucket in unknown_hour_queries) || (bucket in unknown_hour_blocked))) {
				continue
			}
			printf "%s{\"bucket_start\":%d,\"queries\":%d,\"blocked\":%d}", \
				device_comma, bucket, unknown_hour_queries[bucket] + 0, unknown_hour_blocked[bucket] + 0 >> tmp
			device_comma = ","
		}
		printf "]}" >> tmp
		comma = ","
	}
	printf "]}\n" >> tmp
	close(tmp)

	for (bucket = first_hour; bucket <= last_hour; bucket += 3600) {
		delete unknown_hour_queries[bucket]
		delete unknown_hour_blocked[bucket]
	}
	clear_safe_hourly(first_hour, last_hour)
	return replace_file(tmp, path)
}

function save_json(now,    current_hour, first_hour) {
	current_hour = hour_start(now)
	first_hour = statistics_first_hour(now)
	return save_json_range(json_file, now, first_hour, current_hour, 1)
}

function save_upload_json(now,    current_hour, first_hour, retained_first_hour) {
	if (upload_json_file == "") {
		return 1
	}

	current_hour = hour_start(now)
	retained_first_hour = statistics_first_hour(now)
	first_hour = current_hour - ((upload_window_hours - 1) * 3600)
	if (first_hour < retained_first_hour) {
		first_hour = retained_first_hour
	}
	return save_json_range(upload_json_file, now, first_hour, current_hour, 0)
}

function persistence_metadata_signature() {
	return persistent_updated_at SUBSEP persistence_healthy SUBSEP persistent_error_count SUBSEP \
		persistent_last_error_at SUBSEP persistent_compacted_at SUBSEP last_journal_completed_bucket
}

function save_snapshot(now, force_persistent, force_snapshot,    serialize_snapshot, previous_persistence_metadata, persistence_configured) {
	persistence_configured = (persistent_state_file != "" || persistent_journal_file != "")
	serialize_snapshot = snapshot_dirty || force_snapshot || (force_persistent && persistence_configured)
	if (serialize_snapshot) {
		prune_buckets(now)
		# Error-only and unchanged UBus snapshots still refresh source metadata
		# but do not change retained counters. Avoid reaggregating 128 devices
		# across up to 168 hours unless counters, identities, or cutoff changed.
		if (aggregate_dirty) {
			recompute_totals()
			aggregate_dirty = 0
		}
		if (compact_stale_provisional_devices(now) > 0) {
			recompute_totals()
			aggregate_dirty = 0
		}
		updated_at = now
		if (!ensure_snapshot_sequence_reservation(now)) {
			return 0
		}
	}

	previous_persistence_metadata = persistence_metadata_signature()
	maybe_save_persistent(now, force_persistent)
	if (persistence_metadata_signature() != previous_persistence_metadata) {
		serialize_snapshot = 1
	}

	if (!serialize_snapshot) {
		last_snapshot = now
		return 1
	}
	if (!save_state_file(state_file, now)) {
		return 0
	}
	if (!save_json(now)) {
		return 0
	}
	# The cloud-upload projection is auxiliary. A transient tmpfs write failure
	# must not stop local statistics collection; the uploader will retry once a
	# later snapshot is available.
	if (upload_json_file != "") {
		save_upload_json(now)
	}
	snapshot_dirty = 0
	last_snapshot = now
	return 1
}
