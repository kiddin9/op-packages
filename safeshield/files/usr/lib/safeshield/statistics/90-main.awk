# SafeShield statistics: collector lifecycle and dnsmasq event dispatch.
# Loaded together with the other statistics/*.awk modules by safeshield-statsd.

function record_event(query_delta, blocked_delta, client_ip,    now, bucket) {
	if (is_internal_statistics_client(client_ip)) {
		return
	}

	now = current_time()
	bucket = hour_start(now)
	snapshot_dirty = 1
	queries[bucket] += 0
	blocked[bucket] += 0

	if (query_delta > 0) {
		queries[bucket] += query_delta
	}
	if (blocked_delta > 0) {
		blocked[bucket] += blocked_delta
	}

	record_device(client_ip, query_delta, blocked_delta, now)

	event_index++
	if ((now - last_snapshot) >= snapshot_interval) {
		save_snapshot(now, 0, 0)
	}
}

function source_counter_delta(current, previous, same_epoch) {
	current = numeric(current, 0)
	previous = numeric(previous, 0)

	if (!same_epoch || current < previous) {
		return current
	}
	return current - previous
}

function clear_poll_clients(    address) {
	for (address in poll_client_seen) {
		delete poll_client_seen[address]
		delete poll_client_queries[address]
		delete poll_client_blocked[address]
	}
}

function replace_source_clients(    address) {
	for (address in source_client_queries) {
		delete source_client_queries[address]
		delete source_client_blocked[address]
	}
	for (address in poll_client_seen) {
		source_client_queries[address] = poll_client_queries[address] + 0
		source_client_blocked[address] = poll_client_blocked[address] + 0
	}
}

function apply_source_snapshot(    now, bucket, had_source, same_epoch, query_delta, blocked_delta, internal_queries, internal_blocked, address, client_queries_delta, client_blocked_delta) {
	if (!poll_active || poll_instance_id == "") {
		return
	}

	now = current_time()
	bucket = hour_start(now)
	had_source = source_initialized && !force_rebaseline
	same_epoch = had_source && poll_instance_id == source_instance_id

	if (!had_source) {
		query_delta = 0
		blocked_delta = 0
	}
	else {
		query_delta = source_counter_delta(poll_total_queries, source_total_queries, same_epoch)
		blocked_delta = source_counter_delta(poll_total_blocked, source_total_blocked, same_epoch)
	}

	internal_queries = 0
	internal_blocked = 0
	for (address in poll_client_seen) {
		if (!had_source) {
			client_queries_delta = 0
			client_blocked_delta = 0
		}
		else {
			client_queries_delta = source_counter_delta(poll_client_queries[address], \
				source_client_queries[address], same_epoch)
			client_blocked_delta = source_counter_delta(poll_client_blocked[address], \
				source_client_blocked[address], same_epoch)
		}

		if (is_internal_statistics_client(address)) {
			internal_queries += client_queries_delta
			internal_blocked += client_blocked_delta
			continue
		}

		if (client_queries_delta > 0 || client_blocked_delta > 0) {
			record_device(address, client_queries_delta, client_blocked_delta, now)
		}
	}

	query_delta -= internal_queries
	blocked_delta -= internal_blocked
	if (query_delta < 0) {
		query_delta = 0
	}
	if (blocked_delta < 0) {
		blocked_delta = 0
	}

	if (query_delta > 0 || blocked_delta > 0) {
		queries[bucket] += 0
		blocked[bucket] += 0
		queries[bucket] += query_delta
		blocked[bucket] += blocked_delta
	}

	source_initialized = 1
	source_available = 1
	source_instance_id = poll_instance_id
	source_transport_scope = poll_transport_scope
	source_client_capacity = poll_client_capacity
	source_tracked_clients = poll_tracked_clients
	source_untracked_queries = poll_untracked_queries
	source_untracked_blocked = poll_untracked_blocked
	source_total_queries = poll_total_queries
	source_total_blocked = poll_total_blocked
	replace_source_clients()

	poll_active = 0
	clear_poll_clients()
	snapshot_dirty = 1
	event_index++
	if (save_snapshot(now, 0, 0) && force_rebaseline) {
		if (rebaseline_file != "") {
			system("rm -f " shell_quote(rebaseline_file))
		}
		force_rebaseline = 0
	}
}

function record_source_error(    now) {
	now = current_time()
	source_available = 0
	source_error_count++
	source_last_error_at = now
	snapshot_dirty = 1
	event_index++
	save_snapshot(now, 0, 0)
}

BEGIN {
	state_file = (state_file != "") ? state_file : "/tmp/safeshield/statistics/state.tsv"
	json_file = (json_file != "") ? json_file : "/tmp/safeshield/statistics/statistics.json"
	upload_json_file = (upload_json_file != "") ? upload_json_file : ""
	persistent_state_file = (persistent_state_file != "") ? persistent_state_file : ""
	persistent_journal_file = (persistent_journal_file != "") ? persistent_journal_file : ""
	sequence_file = (sequence_file != "") ? sequence_file : ""
	lease_file = (lease_file != "") ? lease_file : "/tmp/dhcp.leases"
	arp_file = (arp_file != "") ? arp_file : "/proc/net/arp"
	ipv6_neigh_file = (ipv6_neigh_file != "") ? ipv6_neigh_file : ""
	ipv6_neigh_command = (ipv6_neigh_command != "") ? ipv6_neigh_command : ""
	ipv6_identity_file = (ipv6_identity_file != "") ? ipv6_identity_file : ""
	ipv6_identity_command = (ipv6_identity_command != "") ? ipv6_identity_command : ""
	snapshot_interval = numeric(snapshot_interval, 60)
	retention_hours = numeric(retention_hours, 168)
	upload_window_hours = numeric(upload_window_hours, 2)
	lease_refresh_interval = numeric(lease_refresh_interval, 60)
	identity_cache_ttl = numeric(identity_cache_ttl, 60)
	provisional_retention_hours = numeric(provisional_retention_hours, 6)
	persistent_interval = numeric(persistent_interval, 3600)
	persistent_retry_interval = numeric(persistent_retry_interval, 300)
	persistent_compact_interval = numeric(persistent_compact_interval, 604800)
	snapshot_seq_reservation_size = numeric(snapshot_seq_reservation_size, 4096)
	max_devices = numeric(max_devices, 128)
	fixed_now = numeric(fixed_now, 0)
	fixed_step = numeric(fixed_step, 0)
	generation_seed = normalize_state_field(generation_seed)
	force_rebaseline = numeric(force_rebaseline, 0) ? 1 : 0
	rebaseline_file = (rebaseline_file != "") ? rebaseline_file : ""
	if (generation_seed == "*") {
		generation_seed = ""
	}
	event_index = 0
	snapshot_dirty = 0
	device_count = 0
	devices_truncated = 0
	last_lease_refresh = 0
	loaded_state = 0
	loaded_from_persistent = 0
	state_schema_version = 1
	snapshot_seq = 0
	snapshot_seq_reserved_through = 0
	persistent_updated_at = 0
	persistent_compacted_at = 0
	last_journal_completed_bucket = 0
	journal_txn_seq = 0
	journal_replaying = 0
	persistence_healthy = (persistent_state_file != "" || persistent_journal_file != "") ? 1 : 0
	persistent_error_count = 0
	persistent_last_error_at = 0
	source_initialized = 0
	source_available = 0
	source_instance_id = ""
	source_transport_scope = ""
	source_client_capacity = 0
	source_tracked_clients = 0
	source_untracked_queries = 0
	source_untracked_blocked = 0
	source_total_queries = 0
	source_total_blocked = 0
	source_error_count = 0
	source_last_error_at = 0
	poll_active = 0

	if (snapshot_interval < 1) {
		snapshot_interval = 60
	}
	if (retention_hours < 1) {
		retention_hours = 168
	}
	if (upload_window_hours < 1 || upload_window_hours > retention_hours) {
		upload_window_hours = (retention_hours < 2) ? retention_hours : 2
	}
	if (lease_refresh_interval < 1) {
		lease_refresh_interval = 60
	}
	if (identity_cache_ttl < 1) {
		identity_cache_ttl = 60
	}
	if (identity_cache_ttl > lease_refresh_interval) {
		identity_cache_ttl = lease_refresh_interval
	}
	if (provisional_retention_hours < 1) {
		provisional_retention_hours = 6
	}
	if (provisional_retention_hours > retention_hours) {
		provisional_retention_hours = retention_hours
	}
	if (persistent_interval < 60) {
		persistent_interval = 3600
	}
	if (persistent_retry_interval < 60) {
		persistent_retry_interval = 300
	}
	if (persistent_compact_interval < 3600) {
		persistent_compact_interval = 604800
	}
	if (snapshot_seq_reservation_size < 64) {
		snapshot_seq_reservation_size = 4096
	}
	if (max_devices < 1) {
		max_devices = 128
	}

	tmp_state_updated_at = state_file_updated_at(state_file)
	persistent_state_updated_at = state_file_updated_at(persistent_state_file)
	persistent_journal_updated_at = journal_file_updated_at(persistent_journal_file)
	persistent_combined_updated_at = persistent_state_updated_at
	if (persistent_journal_updated_at > persistent_combined_updated_at) {
		persistent_combined_updated_at = persistent_journal_updated_at
	}

	tmp_state_snapshot_seq = (tmp_state_updated_at >= 0) ? state_file_snapshot_seq(state_file) : -1
	persistent_state_snapshot_seq = (persistent_state_updated_at >= 0) ? state_file_snapshot_seq(persistent_state_file) : -1
	persistent_journal_snapshot_seq = (persistent_journal_updated_at >= 0) ? journal_file_snapshot_seq(persistent_journal_file) : -1
	tmp_state_generation_id = (tmp_state_updated_at >= 0) ? state_file_generation_id(state_file) : ""
	persistent_state_generation_id = (persistent_state_updated_at >= 0) ? state_file_generation_id(persistent_state_file) : ""
	persistent_journal_generation_id = (persistent_journal_updated_at >= 0) ? journal_file_generation_id(persistent_journal_file) : ""
	persistent_combined_snapshot_seq = persistent_state_snapshot_seq
	persistent_combined_generation_id = persistent_state_generation_id
	if (persistent_journal_snapshot_seq > persistent_combined_snapshot_seq) {
		persistent_combined_snapshot_seq = persistent_journal_snapshot_seq
		persistent_combined_generation_id = persistent_journal_generation_id
	}
	else if (persistent_combined_generation_id == "" && persistent_journal_generation_id != "") {
		persistent_combined_generation_id = persistent_journal_generation_id
	}

	# snapshot_seq is meaningful only inside one generation. A live tmpfs state
	# from a different generation must not lose to a numerically larger sequence
	# left by an older flash generation. Within the same generation, sequence is
	# the primary freshness signal so NTP clock corrections cannot reorder state.
	prefer_persistent_state = 0
	if (tmp_state_updated_at >= 0 && persistent_combined_updated_at >= 0 && \
		tmp_state_generation_id != "" && persistent_combined_generation_id != "" && \
		tmp_state_generation_id != persistent_combined_generation_id) {
		prefer_persistent_state = 0
	}
	else if (tmp_state_snapshot_seq >= 0 || persistent_combined_snapshot_seq >= 0) {
		prefer_persistent_state = (persistent_combined_snapshot_seq > tmp_state_snapshot_seq)
	}
	else {
		prefer_persistent_state = (persistent_combined_updated_at > tmp_state_updated_at)
	}

	if (prefer_persistent_state && persistent_combined_updated_at >= 0) {
		loaded_from_persistent = 1
		if (persistent_state_updated_at >= 0) {
			load_state_file(persistent_state_file)
		}
		if (persistent_journal_updated_at >= 0) {
			load_journal_file(persistent_journal_file, persistent_state_updated_at, snapshot_seq)
		}
	}
	else if (tmp_state_updated_at >= 0) {
		load_state_file(state_file)
	}
	else if (persistent_combined_updated_at >= 0) {
		loaded_from_persistent = 1
		if (persistent_state_updated_at >= 0) {
			load_state_file(persistent_state_file)
		}
		if (persistent_journal_updated_at >= 0) {
			load_journal_file(persistent_journal_file, persistent_state_updated_at, snapshot_seq)
		}
	}

	if (persistent_state_file == "" && persistent_journal_file == "") {
		persistent_updated_at = 0
		persistent_compacted_at = 0
		last_journal_completed_bucket = 0
		persistence_healthy = 1
		persistent_error_count = 0
		persistent_last_error_at = 0
	}
	# started_at identifies the lifetime of the currently retained statistics
	# dataset. It survives collector restarts whenever state can be restored.
	if (started_at <= 0) {
		started_at = current_time()
	}
	# generation_id is the stable identity for that dataset. The stats daemon
	# supplies a fresh candidate on every process start, but restored state wins.
	if (generation_id == "") {
		generation_id = (generation_seed != "") ? generation_seed : sprintf("legacy-%d", started_at)
	}
	durable_snapshot_seq_reserved = load_sequence_reservation(sequence_file, generation_id)
	if (durable_snapshot_seq_reserved > snapshot_seq_reserved_through) {
		snapshot_seq_reserved_through = durable_snapshot_seq_reserved
	}
	# A tmpfs restart can continue with the exact last emitted sequence because
	# save_state_file() precedes save_json(). After a reboot restores flash-backed
	# state, skip the whole durable reservation so a sequence already observed by
	# Hub can never be reused even when the last flash checkpoint was older.
	if (loaded_from_persistent && snapshot_seq_reserved_through > snapshot_seq) {
		snapshot_seq = snapshot_seq_reserved_through
	}
	# session_started_at is process-scoped and intentionally changes every time
	# the collector starts, even when generation_id and started_at are restored.
	session_started_at = current_time()
	migrate_legacy_device_totals(current_time())
	refresh_leases(current_time(), 1)
	last_snapshot = updated_at
	if (last_snapshot <= 0) {
		last_snapshot = session_started_at
	}
	if (persistent_state_file != "" || persistent_journal_file != "") {
		if (last_journal_completed_bucket <= 0 && persistent_updated_at > 0) {
			last_journal_completed_bucket = hour_start(persistent_updated_at) - 3600
		}
		if (persistent_compacted_at <= 0) {
			persistent_compacted_at = (persistent_updated_at > 0) ? persistent_updated_at : current_time()
		}
		schedule_next_persistent(current_time())
		schedule_next_compaction(current_time())
	}
	else {
		next_persistent_at = 0
		next_compact_at = 0
	}
	save_snapshot(current_time(), 0, 1)
}

$1 == "snapshot" && NF >= 9 {
	clear_poll_clients()
	poll_active = 1
	poll_instance_id = $2
	poll_transport_scope = $3
	poll_client_capacity = numeric($4, 0)
	poll_tracked_clients = numeric($5, 0)
	poll_untracked_queries = numeric($6, 0)
	poll_untracked_blocked = numeric($7, 0)
	poll_total_queries = numeric($8, 0)
	poll_total_blocked = numeric($9, 0)
	next
}

$1 == "client" && NF >= 4 && poll_active {
	poll_client_seen[$2] = 1
	poll_client_queries[$2] = numeric($3, 0)
	poll_client_blocked[$2] = numeric($4, 0)
	next
}

$1 == "commit" && poll_active {
	apply_source_snapshot()
	next
}

$1 == "error" {
	poll_active = 0
	clear_poll_clients()
	record_source_error()
	next
}

/dnsmasq\[[0-9]+\]:/ {
	if ($0 ~ / query\[[^]]+\] .* from /) {
		record_event(1, 0, extract_query_client($0))
		next
	}

	if ($0 ~ / config .* is (0\.0\.0\.0|::)([[:space:]]|$)/) {
		record_event(0, 1, extract_extra_client($0))
		next
	}
}

END {
	save_snapshot(current_time(), 1, 0)
}
